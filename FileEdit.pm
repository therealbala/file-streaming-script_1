package Engine::Actions::FileEdit;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(save)] );

use JSON;
use XUtils;

sub main
{
   return $ses->redirect($c->{site_url}) if !$ses->getUser;

   my $adm_mode = 1 if $f->{op} =~ /^admin_/;
   my $redirect_op = $adm_mode ? 'admin_files' : 'my_files';

   my $file = _select_file() || return;

   if ( $c->{rar_info} && $f->{rar_pass_remove} )
   {
      my $res = $ses->api2(
         $file->{srv_id},
         {
            op        => 'rar_password',
            file_id   => $file->{file_real_id} || $file->{file_id},
            file_code => $file->{file_real},
            rar_pass  => $f->{rar_pass},
            file_name => $file->{file_name},
         }
      );
      unless ( $res =~ /Software error/i )
      {
         $db->Exec( "UPDATE Files SET file_spec=? WHERE file_real=?", $res, $file->{file_real} );
      }
      return $ses->redirect("?op=$f->{op}&file_code=$file->{file_code}");
   }
   if ( $c->{rar_info} && $f->{rar_files_delete} && $f->{fname} )
   {
      my $res = $ses->api2(
         $file->{srv_id},
         {
            op        => 'rar_file_del',
            file_name => $file->{file_name},
            file_id   => $file->{file_real_id} || $file->{file_id},
            file_code => $file->{file_real},
            rar_pass  => $f->{rar_pass},
            files     => JSON::encode_json( XUtils::ARef( $f->{fname} ) ),
         }
      );
      unless ( $res =~ /Software error/i )
      {
         $db->Exec( "UPDATE Files SET file_spec=? WHERE file_real=?", $res, $file->{file_code} );
      }
      else
      {
         return $ses->message($res);
      }
      return $ses->redirect("?op=$f->{op}&file_code=$file->{file_code}");
   }
   if ( $c->{rar_info} && $f->{rar_files_extract} && $f->{fname} )
   {
      my $files = join ' ', map { qq["$_"] } @{ XUtils::ARef( $f->{fname} ) };
      my $res = $ses->api2(
         $file->{srv_id},
         {
            op        => 'rar_file_extract',
            file_name => $file->{file_name},
            file_id   => $file->{file_real_id} || $file->{file_id},
            file_code => $file->{file_real},
            rar_pass  => $f->{rar_pass},
            files     => $files,
            files     => JSON::encode_json( XUtils::ARef( $f->{fname} ) ),
            usr_id    => $ses->getUserId,
         }
      );
      return $ses->message($res) unless $res eq 'OK';
      return $ses->redirect("?op=$redirect_op");
   }
   if ( $c->{rar_info} && $f->{rar_split} && $f->{part_size} =~ /^[\d\.]+$/ )
   {
      $f->{part_size} *= 1024;
      my $res = $ses->api2(
         $file->{srv_id},
         {
            op        => 'rar_split',
            file_id   => $file->{file_real_id} || $file->{file_id},
            file_code => $file->{file_real},
            rar_pass  => $f->{rar_pass},
            part_size => "$f->{part_size}k",
            usr_id    => $ses->getUserId,
            file_name => $file->{file_name},
         }
      );
      return $ses->message($res) unless $res eq 'OK';
      return $ses->redirect("?op=$redirect_op");
   }

   if ( $file->{file_name} =~ /\.(rar|zip|7z)$/i && $file->{file_spec} && $c->{rar_info} )
   {
      $file->{rar_nfo} = $file->{file_spec};
      $file->{rar_nfo} =~ s/\r//g;
      $file->{rar_password} = 1 if $file->{rar_nfo} =~ s/password protected\n//ie;
      $file->{rar_nfo} =~ s/\n\n.+$//s;
      my @files;
      my $fld;
      $file->{file_spec} =~ s/\r//g;
      while ( $file->{file_spec} =~ /^(.+?) - ([\d\.]+) (KB|MB)$/gim )
      {
         my $path  = $1;
         my $fname = $1;
         my $fsize = "$2 $3";
         if ( $fname =~ s/^(.+)\/// )
         {
            #push @rf,"<b>$1</b>" if $fld ne $1;
            push @files, { fname => $1, fname2 => "<b>$1</b>" } if $fld ne $1;
            $fld = $1;
         }
         else
         {
            $fld = '';
         }
         $fname = " &nbsp; &nbsp; $fname" if $fld;
         push @files, { fname => $path, fname2 => "$fname - $fsize" };
      }

      #$file->{rar_nfo}.=join "\n", @rf;
      $file->{rar_files} = \@files;
   }

   $file->{file_size2} = sprintf( "%.0f", $file->{file_size} / 1048576 );
   $file->{smartp} = 1 if $ses->iPlg('p') && $c->{m_p_premium_only};

   $ses->PrintTemplate(
      "file_form.html",
      %{$file},
      op       => $f->{op},
      adm_mode => $adm_mode || 0,
      'token'  => $ses->genToken,
      currency_code => $c->{currency_code},
      'allow_vip_files' => $ses->getUser->{usr_allow_vip_files}||$c->{allow_vip_files},
   );
}

sub save
{
   return $ses->redirect($c->{site_url}) if !$ses->getUser;

   my $adm_mode = 1 if $f->{op} =~ /^admin_/;
   my $redirect_op = $adm_mode ? 'admin_files' : 'my_files';

   my $file = _select_file() || return;

   return $ses->message($ses->{lang}->{lang_filename_have_unallowed_extension})
     if ( $c->{ext_allowed} && $f->{file_name} !~ /\.($c->{ext_allowed})$/i )
     || ( $c->{ext_not_allowed} && $f->{file_name} =~ /\.($c->{ext_not_allowed})$/i );
   $f->{file_descr}    = $ses->SecureStr( $f->{file_descr} );
   $f->{file_password} = $ses->SecureStr( $f->{file_password} );
   return $ses->message($ses->{lang}->{lang_filename_too_short}) if length( $f->{file_name} ) < 3;
   $db->Exec(
      "UPDATE Files SET file_name=?, file_descr=?, file_public=?, file_password=?, file_premium_only=?, file_price=? WHERE file_id=?",
      $f->{file_name}, $f->{file_descr}, $f->{file_public}, $f->{file_password}, $f->{file_premium_only}, $f->{file_price}||0,
      $file->{file_id}
   );

   if ($adm_mode)
   {
      $db->Exec( "UPDATE Files SET file_code=? WHERE file_id=?", $f->{file_code}, $file->{file_id} );
      return $ses->redirect("?op=admin_files;fld_id=$file->{file_fld_id}");
   }
   return $ses->redirect("?op=$redirect_op;fld_id=$file->{file_fld_id}");
}

sub _select_file
{
   my $adm_mode = 1 if $f->{op} =~ /^admin_/;

   my $file = $db->SelectRow("SELECT * FROM Files WHERE file_id=?", $f->{file_id} ) || $db->SelectRow( "SELECT * FROM Files WHERE file_code=?", $f->{file_code});
   return $ses->message($ses->{lang}->{lang_no_such_file}) unless $file;
   return $ses->message($ses->{lang}->{lang_not_allowed}) if !$adm_mode && $file->{usr_id} != $ses->getUserId;
   return $file;
}

1;
