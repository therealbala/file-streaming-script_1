package Engine::Actions::AdminNewsEdit;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(save)] );

sub main
{

   my $news = $db->SelectRow( "SELECT * FROM News WHERE news_id=?", $f->{news_id} );
   $news->{created} = $db->SelectOne("SELECT NOW()");
   $ses->PrintTemplate( "admin_news_form.html", %{$news}, 'token' => $ses->genToken, );
}

sub save
{
   return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};
   $f->{news_text}   = $ses->{cgi_query}->param('news_text');
   $f->{news_title2} = lc $f->{news_title};
   $f->{news_title2} =~ s/[^\w\s]//g;
   $f->{news_title2} =~ s/\s+/-/g;
   if ( $f->{news_id} )
   {
      $db->Exec( "UPDATE News SET news_title=?, news_title2=?, news_text=?, created=? WHERE news_id=?",
         $f->{news_title}, $f->{news_title2}, $f->{news_text}, $f->{created}, $f->{news_id} );
   }
   else
   {
      $db->Exec( "INSERT INTO News SET news_title=?, news_title2=?, news_text=?, created=?",
         $f->{news_title}, $f->{news_title2}, $f->{news_text}, $f->{created}, $f->{news_id} );
   }
   return $ses->redirect('?op=admin_news');
}

1;
