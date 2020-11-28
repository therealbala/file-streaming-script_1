package Engine::Actions::AdminReports;
use strict;

use XFileConfig;
use Engine::Core::Action (
   'IMPLEMENTS' => [qw(view decline_selected del_selected ban_selected regenerate_link)],
   'ANTICSRF_WHITELIST' => [qw(view)],
);

use XUtils;

sub main
{
   return $ses->message($ses->{lang}->{lang_access_denied})
     if !$ses->getUser->{usr_adm} && !( $c->{m_d} && $ses->getUser->{usr_mod} && $c->{m_d_a} );

   my $files = _get_files();

   my $filter_status = $f->{history} ? "WHERE status<>'PENDING'" : "WHERE status='PENDING'";
   my $list = $db->SelectARef(
      "SELECT r.*, f.*, ip as ip,
                               (SELECT u.usr_login FROM Users u WHERE r.usr_id=u.usr_id) as usr_login
                               FROM Reports r 
                               LEFT JOIN Files f ON r.file_id = f.file_id
                               $filter_status
                               ORDER BY r.created DESC" . $ses->makePagingSQLSuffix( $f->{page} )
   );
   my $total = $db->SelectOne(
      "SELECT COUNT(*)
                               FROM Reports r
                               $filter_status"
   );
   for (@$list)
   {
      $_->{site_url} = $c->{site_url};
      $_->{file_size2} = sprintf( "%.02f Mb", $_->{file_size} / 1048576 );
      $_->{info} =~ s/\n/<br>/gs;
      $_->{"status_$_->{status}"} = 1;
      $_->{status} .= ', BANNED' if $_->{ban_size};
   }
   $ses->PrintTemplate(
      "admin_reports.html",
      'list'    => $list,
      'paging'  => $ses->makePagingLinks( $f, $total ),
      'history' => $f->{history},
      'token'   => $ses->genToken,
   );
}

sub view
{
   my $report = $db->SelectRow( "SELECT *, ip AS ip2 FROM Reports WHERE id=?", $f->{view} ) || return $ses->message("Report not found");
   return $ses->PrintTemplate( 'admin_report_view.html', %$report );
}

sub decline_selected
{
   my $ids = _get_ids();
   $db->Exec("UPDATE Reports SET status='DECLINED' WHERE id IN ($ids)") if $ids;
   return $ses->redirect("$c->{site_url}/?op=admin_reports");
}

sub del_selected
{
   my $ids = _get_ids();
   my $files = _get_files();

   $db->Exec("UPDATE Reports SET status='APPROVED' WHERE id IN ($ids)") if $ids;
   $ses->DeleteFilesMass($files) if $ids && @$files;
   return $ses->redirect("$c->{site_url}/?op=admin_reports");
}

sub ban_selected
{
   my $files = _get_files();

   for my $file (@$files)
   {
      $db->Exec(
         "UPDATE Reports SET status='APPROVED', ban_size=?, ban_md5=?
            WHERE file_id=?",
         $file->{file_size},
         $file->{file_md5},
         $file->{file_id},
      );
   }
   $ses->DeleteFilesMass($files) if @$files;
   return $ses->redirect("$c->{site_url}/?op=admin_reports");
}

sub regenerate_link
{
   my $files = _get_files();
   for(@$files)
   {
      $db->Exec("UPDATE Files SET file_code=? WHERE file_id=?", $ses->randchar(12), $_->{file_id});
      $db->Exec("UPDATE Reports SET status='APPROVED' WHERE file_id=?", $_->{file_id});
   }
   return $ses->redirect("$c->{site_url}/?op=admin_reports");
}

sub _get_ids
{
   join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{id} ) } ) if $f->{id};
}

sub _get_files
{
   my $ids = _get_ids();

   my $files = $db->SelectARef(
      "SELECT r.id, f.* FROM Reports r
      LEFT JOIN Files f ON f.file_id=r.file_id
      WHERE id IN ($ids)
      AND f.file_id"
   ) if $ids;
}

1;
