package Engine::Actions::AdminApprove;
use strict;

use XFileConfig;
use Engine::Core::Action( 'IMPLEMENTS' => [qw(approve_selected del_selected)] );

use XUtils;

sub main
{
   return $ses->message($ses->{lang}->{lang_access_denied})
     if !$ses->getUser->{usr_adm} && !( $c->{m_d} && $ses->getUser->{usr_mod} && $c->{files_approve} );

   my $list = $db->SelectARef(
      "SELECT f.*, u.*, s.srv_htdocs_url, file_ip AS ip2
      FROM Files f
      LEFT JOIN Users u ON u.usr_id=f.usr_id
      LEFT JOIN Servers s ON s.srv_id=f.srv_id
      WHERE file_awaiting_approve
      ORDER BY file_created DESC"
   );
   for (@$list)
   {
      $_->{download_link} = $ses->makeFileLink($_);

      my $thumbs_dir = $_->{srv_htdocs_url};
      $thumbs_dir =~ s/^(.+)\/.+$/$1\/thumbs/;
      my $dx = sprintf( "%05d", ( $_->{file_real_id} || $_->{file_id} ) / $c->{files_per_folder} );
      if ( $_->{file_name} =~ /\.(avi|divx|xvid|mpg|mpeg|vob|mov|3gp|flv|mp4|wmv|mkv)$/i )
      {
         for my $i ( 1 .. 10 )
         {
            push @{ $_->{series} }, { url => "$thumbs_dir/$dx/$_->{file_real}_$i.jpg" };
         }
      }

      $_->{file_size} = $ses->makeFileSize( $_->{file_size} );
   }
   return $ses->PrintTemplate(
      "admin_approve.html",
      list  => $list,
      token => $ses->genToken,
   );
}

sub approve_selected
{
   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{file_id} ) } ) if $f->{file_id};
   $db->Exec("UPDATE Files SET file_awaiting_approve=0 WHERE file_id IN ($ids)") if $ids;
   return $ses->redirect("$c->{site_url}/?op=$f->{op}");
}

sub del_selected
{
   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{file_id} ) } ) if $f->{file_id};
   my $files = $db->SelectARef("SELECT * FROM Files WHERE file_id IN ($ids)") if $ids;
   $ses->DeleteFilesMass($files) if $files;
   return $ses->redirect("$c->{site_url}/?op=$f->{op}");
}

1;
