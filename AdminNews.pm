package Engine::Actions::AdminNews;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(del_id)] );

sub main
{

   my $news = $db->SelectARef(
      "SELECT n.*, COUNT(c.cmt_id) as comments
                               FROM News n 
                               LEFT JOIN Comments c ON c.cmt_type=2 AND c.cmt_ext_id=n.news_id
                               GROUP BY n.news_id
                               ORDER BY created DESC" . $ses->makePagingSQLSuffix( $f->{page} )
   );
   my $total = $db->SelectOne("SELECT COUNT(*) FROM News");
   for (@$news)
   {
      $_->{site_url} = $c->{site_url};
   }
   $ses->PrintTemplate(
      "admin_news.html",
      'news'   => $news,
      'paging' => $ses->makePagingLinks( $f, $total ),
      'token'  => $ses->genToken,
   );
}

sub del_id
{
   return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};
   $db->Exec( "DELETE FROM News WHERE news_id=?",                       $f->{del_id} );
   $db->Exec( "DELETE FROM Comments WHERE cmt_type=2 AND cmt_ext_id=?", $f->{del_id} );
   return $ses->redirect('?op=admin_news');
}

1;
