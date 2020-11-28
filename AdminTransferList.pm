package Engine::Actions::AdminTransferList;
use strict;

use XFileConfig;
use Engine::Core::Action( 'IMPLEMENTS' => [qw(del_all del_id restart_all restart)] );

sub main
{
   my $list = $db->SelectARef(
      "SELECT q.*, f.*,
                                      UNIX_TIMESTAMP()-UNIX_TIMESTAMP(q.created) as created2,
                                      UNIX_TIMESTAMP()-UNIX_TIMESTAMP(q.updated) as dt,
                                      s1.srv_name as srv_name1, s2.srv_name as srv_name2
                               FROM QueueTransfer q, Files f, Servers s1, Servers s2
                               WHERE q.file_id=f.file_id
                               AND q.srv_id1=s1.srv_id
                               AND q.srv_id2=s2.srv_id
                               ORDER BY started DESC, created
                               LIMIT 1000
                              "
   );
   my @stucked;
   my $token = $ses->genToken();
   for (@$list)
   {
      $_->{site_url} = $c->{site_url};
      my $file_title = $_->{file_title} || $_->{file_name};
      utf8::decode($file_title);
      $_->{file_title_txt} =
        length($file_title) > $c->{display_max_filename_admin}
        ? substr( $file_title, 0, $c->{display_max_filename_admin} ) . '&#133;'
        : $file_title;
      utf8::encode( $_->{file_title_txt} );

      $_->{download_link} = $ses->makeFileLink($_);
      $_->{qstatus} = " <i style='color:green;'>[moving]</i>" if $_->{status} eq 'MOVING';
      if ( $_->{status} eq 'MOVING' && $_->{dt} > 30 )
      {
         push @stucked, $_->{file_real};
         $_->{qstatus} =
           " <i style='color:#c66;'>[stuck]</i> <a href='?op=admin_transfer_list&restart=$_->{file_real}&token=$token'>[restart]</a>";
      }
      if ( $_->{status} =~ /^(ERROR|MOVING)$/ && $_->{error} )
      {
         push @stucked, $_->{file_real};
         $_->{qstatus} =
qq[ <a href="#" onclick="\$('#err_$_->{file_real}').toggle();return false;"><i style="color:#e66;">[error]</i></a><div id='err_$_->{file_real}' style='display:none'>$_->{error}</div>
                           <a href='?op=admin_transfer_list&restart=$_->{file_real}&token=$token'>[restart]</a>];
      }

      $_->{created2} =
        $_->{created2} < 60 ? "$_->{created2} secs"
        : ( $_->{created2} < 7200 ? sprintf( "%.0f", $_->{created2} / 60 ) . ' mins'
         : sprintf( "%.0f", $_->{created2} / 3600 ) . ' hours' );
      $_->{created2} .= ' ago';
      $_->{started2} = '' if $_->{started} eq '0000-00-00 00:00:00';

      $_->{progress}       = sprintf( "%.0f",    100 * $_->{transferred} / $_->{file_size} ) if $_->{file_size};
      $_->{file_size}      = sprintf( "%.0f MB", $_->{file_size} / 1024 / 1024 );
      $_->{transferred_mb} = sprintf( "%.01f",   $_->{transferred} / 1024 / 1024 );

      # Prevent odd speeds from being displayed
      $_->{is_starting} = 1 if $_->{transferred} < 2**20 && $_->{status} eq 'MOVING';
   }
   my $srv_list = $db->SelectARef(
      "SELECT s.srv_name,
                                   SUM(IF(q.status='PENDING',1,0)) as num_pending,
                                   SUM(IF((q.status='MOVING' AND q.updated>=NOW()-INTERVAL 60 SECOND),1,0)) as num_moving,
                                   SUM(IF((q.status='MOVING' AND q.updated<NOW()-INTERVAL 60 SECOND),1,0)) as num_stucked,
                                   SUM(IF(q.status='ERROR',1,0)) as num_error
                                   FROM QueueTransfer q, Servers s
                                   WHERE q.srv_id2=s.srv_id
                                   GROUP BY srv_id2
                                  "
   );
   $ses->PrintTemplate(
      "admin_transfer_list.html",
      list       => $list,
      restartall => @stucked > 0 ? join( ',', @stucked ) : 0,
      srv_list   => $srv_list,
      'token'    => $ses->genToken,
   );
}

sub del_id
{
   $db->Exec( "DELETE FROM QueueTransfer WHERE file_real=? LIMIT 1", $f->{del_id} );
   return $ses->redirect('?op=admin_transfer_list');
}

sub restart
{
   $db->Exec( "UPDATE QueueTransfer SET status='PENDING', error='' WHERE file_real=? LIMIT 1", $f->{restart} );
   return $ses->redirect('?op=admin_transfer_list');
}

sub del_all
{
   $db->Exec("DELETE FROM QueueTransfer");
   return $ses->redirect('?op=admin_transfer_list');
}

sub restart_all
{
   if($f->{ids})
   {
      my $ids = join("','", grep { /^\w{12}$/ } split(/,\s*/, $f->{ids}));
      $db->Exec("UPDATE QueueTransfer SET status='PENDING', error='' WHERE file_real IN ('$ids')") if $ids;
   }
   else
   {
      $db->Exec("UPDATE QueueTransfer SET status='PENDING', error=''");
   }
   return $ses->redirect('?op=admin_transfer_list');
}

1;
