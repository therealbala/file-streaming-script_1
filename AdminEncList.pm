package Engine::Actions::AdminEncList;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(cancel restart delete restart_stuck restart_errors delete_errors)] );
use XUtils;

sub main
{
   my $filter_srv="AND q.srv_id=$f->{srv_id}" if $f->{srv_id}=~/^\d+$/;
   my $filter_user="AND q.usr_id=$f->{usr_id}" if $f->{usr_id}=~/^\d+$/;
    $f->{per_page}||=100;
    my $list = $db->SelectARef("SELECT q.*, UNIX_TIMESTAMP()-UNIX_TIMESTAMP(q.started) as started2,
                                      UNIX_TIMESTAMP()-UNIX_TIMESTAMP(q.updated) as updated2,
                                      f.file_size, f.usr_id, f.file_code, f.file_name,
                                      u.usr_login,
                                      s.srv_name,
                                      UNIX_TIMESTAMP()-UNIX_TIMESTAMP(created) as dt
                               FROM QueueEncoding q
                               LEFT JOIN Files f ON f.file_id=q.file_id
                               LEFT JOIN Users u ON u.usr_id=f.usr_id
                               LEFT JOIN Servers s ON s.srv_id=f.srv_id
                               WHERE q.file_id=f.file_id
                               $filter_srv
                               $filter_user
                               ORDER BY status DESC
                              ".$ses->makePagingSQLSuffix($f->{page}));
    my $total = $db->SelectOne("SELECT COUNT(*)
                                FROM QueueEncoding q
                                WHERE 1
                                $filter_srv
                                $filter_user");

   my ($stucked,$errors);
   for(@$list)
   {
      $_->{site_url} = $c->{site_url};
      $_->{file_name_txt} = shorten($_->{file_name});

      $_->{file_size2} = $ses->makeFileSize($_->{file_size});
      $_->{download_link} = $ses->makeFileLink($_);
      $_->{file_length2} = sprintf("%02d:%02d:%02d",int($_->{file_length}/3600),int(($_->{file_length}%3600)/60),$_->{file_length}%60);
      if($_->{started} eq '0000-00-00 00:00:00')
      {
        $_->{started2}='';
      }
      else
      {
        $_->{started2} = $_->{started2}<60 ? "$_->{started2} sec" : ($_->{started2}<7200 ? sprintf("%.0f",$_->{started2}/60).' min' : sprintf("%.0f",$_->{started2}/3600).' hours');
        $_->{started2}.=' ago';
      }
      $_->{qstatus}='<i style="color:green;">[encoding]</i>' if $_->{status} eq 'ENCODING';
      if($_->{status} eq 'ENCODING' && $_->{updated2} > 60)
      {
         $_->{restart}=1;
         $_->{qstatus}='<i style="color:#c66;">[stuck]</i>';
         $stucked++;
      }
      if($_->{status} eq 'ENCODING' && $_->{error})
      {
         $_->{restart}=1;
         $_->{qstatus}=qq[<a href="#" onclick="\$('#err$_->{file_real}').toggle();return false;"><i style="color:#e66;">[error]</i></a><div id='err$_->{file_real}' style='display:none'>$_->{error}</div>];
         $errors++;
      }
   }

   $ses->PrintTemplate("admin_enc_list.html",
                       list => $list,
                       paging => $ses->makePagingLinks($f,$total),
                       restart_stuck => $stucked,
                       restart_error => $errors);
}

sub cancel
{
   for (@{XUtils::ARef($f->{file_real})})
   {
      $db->Exec("DELETE FROM QueueEncoding WHERE file_real=? LIMIT 1", $_);
   }
   $ses->redirect('?op=admin_enc_list');
}

sub restart
{
   for (@{XUtils::ARef($f->{file_real})})
   {
     $db->Exec("UPDATE QueueEncoding
                SET status='PENDING',
                    progress=0,
                    fps=0,
                    error='',
                    started='0000-00-00 00:00:00',
                    updated='0000-00-00 00:00:00'
                WHERE file_real=? LIMIT 1", $_);
   }
   $ses->redirect('?op=admin_enc_list');
}

sub delete
{
   for (@{XUtils::ARef($f->{file_real})})
   {
      my $file = $db->SelectRow("SELECT * FROM Files WHERE file_real=?", $_);
      next unless $file;
      $ses->DeleteFile($file);
   }
   $ses->redirect('?op=admin_enc_list');
}

sub restart_stuck
{
   $db->Exec("UPDATE QueueEncoding
              SET status='PENDING',
                  progress=0,
                  fps=0,
                  error='',
                  started='0000-00-00 00:00:00',
                  updated='0000-00-00 00:00:00'
              WHERE status='ENCODING'
              AND updated < NOW()-INTERVAL 1 MINUTE");
   $ses->redirect('?op=admin_enc_list');
}

sub restart_errors
{
   $db->Exec("UPDATE QueueEncoding
              SET status='PENDING',
                  progress=0,
                  fps=0,
                  error='',
                  started='0000-00-00 00:00:00',
                  updated='0000-00-00 00:00:00'
              WHERE status='ENCODING'
              AND error<>''
              AND updated < NOW()-INTERVAL 1 MINUTE
              ");
   $ses->redirect('?op=admin_enc_list');
}

sub delete_errors
{
   $db->Exec("DELETE FROM QueueEncoding
              WHERE status='ENCODING'
              AND error<>''
              AND updated < NOW()-INTERVAL 1 MINUTE
             ");
   $ses->redirect('?op=admin_enc_list');
}

sub shorten
{
   my ( $str, $max_length ) = @_;
   $max_length ||= $c->{display_max_filename};
   return length($str) > $max_length ? substr( $str, 0, $max_length ) . '&#133;' : $str;
}

1;
