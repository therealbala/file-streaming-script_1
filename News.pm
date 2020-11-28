package Engine::Actions::News;
use strict;

use XFileConfig;
use Engine::Core::Action;

sub main
{
   my $news = $db->SelectARef(
      "SELECT n.*, DATE_FORMAT(n.created,'%M %dth, %Y') as created_txt,
                                      COUNT(c.cmt_id) as comments
                               FROM News n
                               LEFT JOIN Comments c ON c.cmt_type=2 AND c.cmt_ext_id=n.news_id
                               WHERE n.created<=NOW()
                               GROUP BY n.news_id
                               ORDER BY n.created DESC" . $ses->makePagingSQLSuffix( $f->{page} )
   );
   my $total = $db->SelectOne("SELECT COUNT(*) FROM News WHERE created<NOW()");
   for (@$news)
   {
      $_->{site_url} = $c->{site_url};
      $_->{news_text} =~ s/\n/<br>/gs;
      $_->{enable_file_comments} = $c->{enable_file_comments};
   }
   $ses->PrintTemplate(
      "news.html",
      'news'   => $news,
      'paging' => $ses->makePagingLinks( $f, $total ),
   );
}

1;
