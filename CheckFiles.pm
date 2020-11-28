package Engine::Actions::CheckFiles;
use strict;

use XFileConfig;
use Engine::Core::Action;
use Math::Base62;

sub main
{
   $f->{list} =~ s/\r//gs;
   my ( $i, @arr );
   for ( split /\n/, $f->{list} )
   {
      $i++;
      my $link = parse_short_link($_) || parse_full_link($_);
      next if !$link;

      my $file = $link->{short_id}
         ? $db->SelectRow("SELECT * FROM Files WHERE file_id=?", Math::Base62::decode_base62($link->{short_id}))
         : $db->SelectRow("SELECT * FROM Files WHERE file_code=?", $link->{code});

      my $server = $db->SelectRow("SELECT * FROM Servers WHERE srv_id=?", $file->{srv_id});

      push( @arr, { url => $_, color => 'red', status => "Not found!" } ), next if !$file || !$file->{file_id};
      $file->{file_name} =~ s/_/ /g;
      push( @arr, { url => $_, color => 'red', status => "Filename don't match!" } ), next
        if $link->{fname} && $file->{file_name} ne $link->{fname};
      push( @arr, { url => $_, color => 'orange', status => "Found. Server is not available at the moment" } ), next
        if !$server || $server->{srv_status} eq 'OFF';
      $file->{fsize} = $ses->makeFileSize( $file->{file_size} );
      push( @arr, { url => $_, color => 'green', status => "Found", fsize => $file->{fsize} } );
   }
   $ses->PrintTemplate( "checkfiles.html", 'list' => \@arr, );
}

sub parse_full_link
{
   my ($str) = @_;
   my ( $code, $fname ) = $str =~ /\w\/(\w{12})\/?(.*?)$/;
   return if !$code;

   $fname =~ s/\.html?$//i;
   $fname =~ s/_/ /g;
   return { code => $code, fname => $fname };
}

sub parse_short_link
{
   my ($str) = @_;
   my ($short_id) = $str =~ /\/d\/(\w+)$/;
   return if !$short_id;
   return { short_id => $short_id };
}

1;
