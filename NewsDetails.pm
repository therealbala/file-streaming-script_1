package Engine::Actions::NewsDetails;
use strict;

use XFileConfig;
use Engine::Core::Action;
use XUtils;

sub main
{
   my $news = $db->SelectRow(
      "SELECT *, DATE_FORMAT(created,'%M %e, %Y at %r') as date 
                              FROM News 
                              WHERE news_id=? AND created<=NOW()", $f->{news_id}
   );
   return $ses->message($ses->{lang}->{lang_no_such_news}) unless $news;
   $news->{news_text} = $ses->UnsecureStr($news->{news_text});
   $news->{news_text} =~ s/\n/<br>/gs;
   my $comments = XUtils::CommentsList( 2, $f->{news_id} );
   $ses->{page_title} = $ses->{meta_descr} = $news->{news_title};
   $ses->PrintTemplate(
      "news_details.html",
      %{$news},
      'cmt_type'             => 2,
      'cmt_ext_id'           => $news->{news_id},
      'comments'             => $comments,
      'enable_file_comments' => $c->{enable_file_comments},
      'token_admin_comments' => $ses->genToken(op => 'admin_comments'),
      'token_comments'       => $ses->genToken(op => 'comments'),
   );
}

1;
