package Engine::Actions::Comments;
use strict;

use XFileConfig;
use Engine::Core::Action( 'IMPLEMENTS' => [qw(add del)] );

use XUtils;

sub main
{
   return $ses->redirect($c->{site_url});
}

sub add
{
   return $ses->message("File comments are not allowed") if $f->{cmt_type} == 1 && !$c->{enable_file_comments};
   print(
qq{Content-type:text/html\n\n\$\$('cnew').innerHTML+="<b class='err'>Comments enabled for registered users only!</b><br><br>"}
     ), return
     if $c->{comments_registered_only} && !$ses->getUser;
   die("Invalid object ID") unless $f->{cmt_ext_id} =~ /^\d+$/;
   if ( $ses->getUser )
   {
      $f->{cmt_name}  = $ses->getUser->{usr_login};
      $f->{cmt_email} = $ses->getUser->{usr_email};
   }
   $f->{usr_id} = $ses->getUser ? $ses->getUserId : 0;
   $f->{cmt_name} =~ s/(http:\/\/|www\.|\.com|\.net)//gis;
   $f->{cmt_name}  = $ses->SecureStr( $f->{cmt_name} );
   $f->{cmt_email} = $ses->SecureStr( $f->{cmt_email} );
   $f->{cmt_text}  = $ses->SecureStr( $f->{cmt_text} );
   $f->{cmt_text} =~ s/(\_n\_|\n)/<br>/g;
   $f->{cmt_text} =~ s/\r//g;
   $f->{cmt_text} = substr( $f->{cmt_text}, 0, 800 );
   $f->{cmt_name} ||= 'Anonymous';

   local *error = sub {
      print(qq{Content-type:text/html\n\n<b class='err'>$_[0]</b>}), return if $f->{cmt_type} == 1;
      return $ses->message( $_[0] );
   };

   return &error("E-mail is not valid")
     if $f->{cmt_email} && $f->{cmt_email} !~ /^([a-zA-Z0-9_\.\-])+\@(([a-zA-Z0-9\-])+\.)+([a-zA-Z0-9]{2,4})+$/;
   return &error("Too short comment text") if length( $f->{cmt_text} ) < 5;

   my $txt = $f->{cmt_text};
   $txt =~ s/[\s._-]+//gs;
   return &error("Comment text contain restricted word") if $c->{bad_comment_words} && $txt =~ /$c->{bad_comment_words}/i;

   $db->Exec(
      "INSERT INTO Comments
              SET usr_id=?,
                  cmt_type=?,
                  cmt_ext_id=?,
                  cmt_ip=?,
                  cmt_name=?,
                  cmt_email=?,
                  cmt_text=?
             ", $f->{usr_id}, $f->{cmt_type}, $f->{cmt_ext_id}, $ses->getIP, $f->{cmt_name}, $f->{cmt_email} || '',
      $f->{cmt_text}
   );
   my $comment = $db->SelectRow(
      "SELECT *, cmt_ip as ip, DATE_FORMAT(created,'%M %e, %Y') as date, DATE_FORMAT(created,'%r') as time
                  FROM Comments
                  WHERE cmt_id=?",
      $db->getLastInsertId
   );
   my $news = $db->SelectRow( "SELECT * FROM News WHERE news_id=?", $f->{cmt_ext_id} );
   $ses->setCookie( 'cmt_name',  $f->{cmt_name} );
   $ses->setCookie( 'cmt_email', $f->{cmt_email} );
   return $f->{cmt_type} == 1
     ? $ses->PrintTemplate2( "comment.html", %$comment )
     : $ses->redirect( $ses->getEnv('HTTP_REFERER') );
}

sub del
{
   return $ses->message($ses->{lang}->{lang_access_denied}) unless $ses->getUser && $ses->getUser->{usr_adm};
   $db->Exec( "DELETE FROM Comments WHERE cmt_id=?", $f->{cmt_id} );
   return $ses->redirect( $ses->getEnv('HTTP_REFERER') );
}

1;
