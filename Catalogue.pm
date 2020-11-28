package Engine::Actions::Catalogue;
use strict;

use XFileConfig;
use Engine::Core::Action;

sub main
{
   return $ses->redirect( $c->{site_url} ) unless $c->{enable_catalogue};
   return $ses->message($ses->{lang}->{lang_catalogue_reg_only}) if $c->{catalogue_registered_only} && !$ses->getUser;
   $f->{page} ||= 1;
   $f->{per_page} = 30;
   my $exts = {
      'vid' => 'avi|mpg|mpeg|mkv|wmv|mov|3gp|vob|asf|qt|m2v|divx|mp4|flv|rm',
      'aud' => 'mp3|wma|ogg|flac|wav|aac|m4a|mid|mpa|ra',
      'img' => 'jpg|jpeg|png|gif|bmp|eps|ps|psd|tif',
      'arc' => 'zip|rar|7z|gz|pkg|tar',
      'app' => 'exe|msi|app|com'
   }->{ $f->{ftype} };
   my $filter_ext = "AND file_name REGEXP '\.($exts)\$' " if $exts;
   my $fsize_logic = $f->{fsize_logic} eq 'gt' ? '>' : '<';
   my $filter_size = "AND file_size $fsize_logic " . ( $f->{fsize} * 1048576 ) if $f->{fsize};
   my $filter = "AND (file_name LIKE '%$f->{k}%' OR file_descr LIKE '%$f->{k}%')" if $f->{k} =~ /^[^\"\'\;\\]{3,}$/;
   my $list = $db->SelectARef(
      "SELECT f.*,
                                      TO_DAYS(CURDATE())-TO_DAYS(file_created) as created,
                                      s.srv_htdocs_url
                               FROM Files f, Servers s
                               WHERE file_public=1
                               AND f.srv_id=s.srv_id
                               $filter
                               $filter_ext
                               $filter_size
                               ORDER BY file_created DESC" . $ses->makePagingSQLSuffix( $f->{page} )
   );
   my $total = $db->SelectOne(
      "SELECT COUNT(*)
                               FROM Files f
                               WHERE file_public=1
                               $filter
                               $filter_ext
                               $filter_size"
   );
   my $paging = $ses->makePagingLinks( $f, $total, 'reverse' );

   my $cx;
   for (@$list)
   {
      $_->{site_url} = $c->{site_url};
      utf8::decode( $_->{file_descr} );
      $_->{file_descr} = substr( $_->{file_descr}, 0, 48 ) . '&#133;' if length( $_->{file_descr} ) > 48;
      utf8::encode( $_->{file_descr} );
      $_->{file_size}     = $ses->makeFileSize( $_->{file_size} );
      $_->{download_link} = $ses->makeFileLink($_);
      $_->{file_name} =~ s/_/ /g;
      my ($ext) = $_->{file_name} =~ /\.(\w+)$/i;

      my $file_name = $_->{file_name};
      utf8::decode($file_name);
      $_->{file_name_txt} = shorten( $file_name, 30 );
      utf8::encode( $_->{file_name_txt} );

      $ext = lc $ext;
      $_->{img_preview} =
        $ext =~
/^(ai|aiff|asf|avi|bmpbz2|css|doc|eps|gif|gz|html|jpg|jpeg|mid|mov|mp3|mpg|mpeg|ogg|pdf|png|ppt|ps|psd|qt|ra|ram|rm|rpm|rtf|tgz|tif|torrent|txt|wav|xls|xml|zip|exe|flv|swf|qma|wmv|mkv|rar)$/
        ? "$c->{site_url}/images/icons/$ext-dist.png"
        : "$c->{site_url}/images/icons/default-dist.png";
      $_->{add_to_account} = 1 if $ses->getUser && $_->{usr_id} != $ses->getUserId;
      if (  ( $c->{m_i} && $_->{file_name} =~ /\.(jpg|jpeg|gif|png|bmp)$/i )
         || ( $c->{m_v} && $_->{file_name} =~ /\.(avi|divx|flv|mp4|wmv|mkv)$/i ) )
      {
         my $iurl = $_->{srv_htdocs_url};
         $iurl =~ s/^(.+)\/.+$/$1\/i/;
         my $dx = sprintf( "%05d", ( $_->{file_real_id} || $_->{file_id} ) / $c->{files_per_folder} );
         $_->{img_preview2} = "$iurl/$dx/$_->{file_real}_t.jpg";
      }
      $_->{'tr'} = 1 if ++$cx % 3 == 0;
   }
   $ses->{header_extra} =
qq{<link rel="alternate" type="application/rss+xml" title="$c->{site_name} new files" href="$c->{site_url}/catalogue.rss">};
   $ses->{page_title} = "$c->{site_name} File Catalogue: page $f->{page}";

   #die $f->{k};
   $ses->PrintTemplate(
      "catalogue.html",
      'files'  => $list,
      'paging' => $paging,
      'date'   => $f->{date},
      'k'      => $f->{k},
      'fsize'  => $f->{fsize},
      'token_my_files' => $ses->genToken(op => 'my_files'),
   );
}

sub shorten
{
   my ( $str, $max_length ) = @_;
   $max_length ||= $c->{display_max_filename};
   return length($str) > $max_length ? substr( $str, 0, $max_length ) . '&#133;' : $str;
}

1;
