package Engine::Actions::AdminComments;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(del_selected)] );

use XUtils;

sub main
{
   return $ses->message($ses->{lang}->{lang_access_denied})
     if !$ses->getUser->{usr_adm} && !( $c->{m_d} && $ses->getUser->{usr_mod} && $c->{m_d_c} );

   my $filter;
   $filter = "WHERE c.cmt_ip='$f->{ip}'" if $f->{ip};
   $filter = "WHERE c.usr_id=$f->{usr_id}"          if $f->{usr_id};
   $filter = "WHERE c.cmt_name LIKE '%$f->{key}%' OR c.cmt_email LIKE '%$f->{key}%' OR c.cmt_text LIKE '%$f->{key}%'"
     if $f->{key};
   my $list = $db->SelectARef(
      "SELECT c.*, c.cmt_ip as ip, u.usr_login, u.usr_id,
                                 f.file_name, f.file_code,
                                 n.news_id, n.news_title
                               FROM Comments c
                               LEFT JOIN Users u ON c.usr_id=u.usr_id
                               LEFT JOIN Files f ON f.file_id=c.cmt_ext_id
                               LEFT JOIN News n ON n.news_id=c.cmt_ext_id
                               $filter
                               ORDER BY created DESC" . $ses->makePagingSQLSuffix( $f->{page}, $f->{per_page} )
   );
   my $total = $db->SelectOne("SELECT COUNT(*) FROM Comments c $filter");

   for (@$list)
   {
      $_->{"cmt_type_$_->{cmt_type}"} = 1;
      $_->{download_link}             = $ses->makeFileLink($_);
      $_->{news_link}                 = "$c->{site_url}/n$_->{news_id}-" . lc( $_->{news_title} ) . ".html";
   }

   $ses->PrintTemplate(
      "admin_comments.html",
      'list'   => $list,
      'key'    => $f->{key},
      'paging' => $ses->makePagingLinks( $f, $total ),
      'token'  => $ses->genToken,
   );
}

sub del_selected
{
   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{cmt_id} ) } );
   return $ses->redirect( $c->{site_url} ) unless $ids;
   $db->Exec("DELETE FROM Comments WHERE cmt_id IN ($ids)");
   return $ses->redirect($ENV{HTTP_REFERER} || "?op=admin_comments");
}

1;
