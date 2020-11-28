package Engine::Actions::AdminCommentEdit;
use strict;

use XFileConfig;
use Engine::Core::Action( 'IMPLEMENTS' => [qw(save)] );

sub main
{
   my $comment = $db->SelectRow(
      "SELECT *, u.usr_login, cmt_ip AS ip,
         f.file_name, f.file_code,
         n.news_title,
         c.created
      FROM Comments c
      LEFT JOIN Users u ON u.usr_id=c.usr_id
      LEFT JOIN Files f ON f.file_id=c.cmt_ext_id
      LEFT JOIN News n ON n.news_id=c.cmt_ext_id
      WHERE cmt_id=?", $f->{cmt_id}
   );
   return $ses->PrintTemplate(
      "admin_comment_form.html",
      %{$comment},
      download_link                   => $ses->makeFileLink($comment),
      "cmt_type_$comment->{cmt_type}" => 1,
      token                           => $ses->genToken
   );
}

sub save
{
   $db->Exec( "UPDATE Comments SET cmt_text=? WHERE cmt_id=?", $f->{cmt_text}, $f->{cmt_id} );
   return $ses->redirect("$c->{site_url}/?op=admin_comments");
}

1;
