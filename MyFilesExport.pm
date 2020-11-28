package Engine::Actions::MyFilesExport;
use strict;

use XFileConfig;
use Engine::Core::Action;

use XUtils;

sub main
{
   my $filter;
   if ( $f->{"file_id[]"} )
   {
      my $ids = join ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{"file_id[]"} ) };
      $filter = "AND file_id IN ($ids)" if $ids;
   }
   else
   {
      $filter = "AND file_fld_id='$f->{fld_id}'" if $f->{fld_id} =~ /^\d+$/;
   }
   my $list = $db->SelectARef(
      "SELECT * FROM Files f, Servers s
                               WHERE usr_id=? 
                               AND f.srv_id=s.srv_id
                               $filter 
                               ORDER BY file_name", $ses->getUserId
   );
   print $ses->{cgi_query}->header(
      -type    => 'text/html',
      -expires => '-1d',
      -charset => $c->{charset}
   );
   my ( @list, @list_bb, @list_html, @list_deurl );
   for my $file (@$list)
   {
      $file->{download_link} = $ses->makeFileLink($file);
      if ( $c->{m_i} && $file->{file_name} =~ /\.(jpg|jpeg|gif|png|bmp)$/i )
      {
         $ses->getThumbLink($file);
      }
      else
      {
         $file->{fsize} = $ses->makeFileSize( $file->{file_size} );
      }
      push @list, $file->{download_link};
      push @list_bb,
        $file->{thumb_url}
        ? "[URL=$file->{download_link}][IMG]$file->{thumb_url}\[\/IMG]\[\/URL]"
        : "[URL=$file->{download_link}]$file->{file_name} - $file->{fsize}\[\/URL]";
      push @list_html,
        $file->{thumb_url}
        ? qq[<a href="$file->{download_link}" target=_blank><img src="$file->{thumb_url}" border=0><\/a>"]
        : qq[<a href="$file->{download_link}" target=_blank>$file->{file_name} - $file->{fsize}<\/a>];

      if($c->{m_j})
      {
         my $short_link = $ses->shortenURL( $file->{file_id} );
         push @list_deurl,
           $file->{thumb_url}
           ? qq[<a href="$short_link" target=_blank><img src="$file->{thumb_url}" border=0><\/a>"]
           : qq[<a href="$short_link" target=_blank>$file->{file_name} - $file->{fsize}<\/a>];
      }
   }
   print "<HTML><BODY style='font: 13px Arial;'>";
   print "<b>Download links</b><br><textarea cols=100 rows=5 wrap=off>" . join( "\n", @list ) . "<\/textarea><br><br>";
   print "<b>Forum code</b><br><textarea cols=100 rows=5 wrap=off>" . join( "\n", @list_bb ) . "<\/textarea><br><br>";
   print "<b>HTML code</b><br><textarea cols=100 rows=5 wrap=off>" . join( "\n", @list_html ) . "<\/textarea><br><br>";
   print "<b>Short links</b><br><textarea cols=100 rows=5 wrap=off>" . join( "\n", @list_deurl ) . "<\/textarea><br><br>" if $c->{m_j};
   return;
}

1;
