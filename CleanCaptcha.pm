package Engine::Cronjobs::CleanCaptcha;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;

sub main
{
   return if $c->{captcha_mode} != 1;
   print "Cleaning up old captchas...\n";

   opendir( DIR, "$c->{site_path}/captchas" );
   while ( defined( my $fn = readdir(DIR) ) )
   {
      next if $fn =~ /^\.{1,2}$/;
      my $file = "$c->{site_path}/captchas/$fn";
      unlink($file) if ( time - ( lstat($file) )[9] ) > 1800;
   }
   closedir DIR;
}

1;
