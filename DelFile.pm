package Engine::Actions::DelFile;
use strict;
use Digest::MD5 qw(md5_hex);

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [ qw(confirm) ]);

use XUtils;
use List::Util qw(min);

sub main
{
   my $file = _select_file() || return;

   $ses->PrintTemplate("delete_file.html",
                       'confirm' =>1,
                       'id'      => $f->{id},
                       'del_id'  => $f->{del_id},
                       'fname'   => $file->{file_name},
                      );
}

sub confirm
{
   my $file = _select_file() || return;

   $ses->DeleteFile($file);
   $ses->PrintTemplate("delete_file.html", 'status'=>$ses->{lang}->{lang_file_deleted});
}

sub _select_file
{
   my $file = $db->SelectRow("SELECT * FROM Files f, Servers s
                              WHERE file_code=?
                              AND f.srv_id=s.srv_id",$f->{id});
   $ses->message('No such file exist'), return unless $file;
   $ses->message('Server with this file is Offline'), return if $file->{srv_status} eq 'OFF';
   $ses->message('Wrong Delete ID'), return if $file->{file_del_id} ne $f->{del_id};
   
   return $file;
}

1;
