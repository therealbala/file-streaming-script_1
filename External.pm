package Engine::Actions::External;
use strict;
use XUtils;

use XFileConfig;
use Engine::Core::Action;

use XUtils;

sub main
{
   my $key = _get_key();
   return $ses->PrintJSON( { err => "Unauthorized" } ) if !$key;
   return $ses->PrintJSON( { err => "No action" } ) if !$f->{download} && !$f->{upload};

   for (qw(download upload))
   {
      return $ses->PrintJSON( { err => "Access denied: '$_'" } ) if $f->{$_} && !$key->{"perm_$_"};
   }

   # Explicitly avoid Anti-CSRF check
   return download() if $f->{download};
   return upload() if $f->{upload};
}

sub download
{
   my $key = _get_key();
   update_api_stats( $key, inc_downloads => 1 );

   my $file = $db->SelectRow(
      "SELECT f.*, s.* FROM Files f
            LEFT JOIN Servers s ON s.srv_id=f.srv_id 
            WHERE file_code=?",
      $f->{file_code}
   );
   return $ses->PrintJSON( { err => "No such file" } ) if !$file;

   update_api_stats( $key, inc_bandwidth_out => $file->{file_size} );

   return $ses->PrintJSON( { direct_link => $ses->getPlugins('CDN')->genDirectLink($file) } );
}

sub upload
{
   my $key = _get_key();
   my $user = $ses->require("Engine::Components::Auth")->checkLoginPass($f->{login}, $f->{password});
   return $ses->PrintJSON({ err => "Invalid login/pass" }) if $f->{login} && !$user;
   
   # Need to create a new session even for anonymous user in
   # order to register the stats after the file will be uploaded
   my $sess_id = $ses->require("Engine::Components::SessionTracker")->GetSession($user ? $user->{usr_id} : 0);
   die("No session") if !$sess_id;
   $db->Exec("UPDATE Sessions SET api_key_id=? WHERE session_id=?", $key->{key_id}, $sess_id);
   my $server = XUtils::SelectServer($ses, $user);
   my $utype = $user && $user->{utype} ? $user->{utype} : 'anon';
   
   return $ses->PrintJSON({
      upload_url => "$server->{srv_cgi_url}/upload.cgi?utype=$utype",
      sess_id => $sess_id,
   });
}

sub update_api_stats
{
   my ( $key, %opts ) = @_;

   my @params = map { $opts{"inc_$_"} || 0 } qw(uploads downloads bandwidth_in bandwidth_out);

   $db->Exec(
      "INSERT INTO APIStats SET key_id=?, day=CURDATE(),
      uploads=?, downloads=?, bandwidth_in=?, bandwidth_out=?
      ON DUPLICATE KEY UPDATE uploads=uploads+?, downloads=downloads+?, bandwidth_in=bandwidth_in+?, bandwidth_out=bandwidth_out+?",
      $key->{key_id},
      @params,
      @params
   );
}

sub _get_key
{
   my ( $key_id, $key_code ) = $f->{api_key} =~ /^(\d+)(\w+)$/;
   my $key = $db->SelectRow( "SELECT * FROM APIKeys WHERE key_id=? AND key_code=?", $key_id, $key_code );
   return $key;
}

1;
