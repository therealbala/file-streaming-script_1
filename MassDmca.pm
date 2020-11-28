package Engine::Actions::MassDmca;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(urls)] );

use XUtils;

sub main
{
   return $ses->redirect($c->{site_url}) if !$ses->getUser;
   return $ses->message($ses->{lang}->{lang_access_denied}) if !( $c->{m_d} && $ses->getUser->{usr_dmca_agent} );
   return $ses->PrintTemplate( 'mass_dmca.html', dmca_hours => $c->{dmca_hours} );
}

sub urls
{
   return $ses->redirect($c->{site_url}) if !$ses->getUser;
   return $ses->message($ses->{lang}->{lang_access_denied}) if !( $c->{m_d} && $ses->getUser->{usr_dmca_agent} );

   my @urls = split( /\n\r?/, $f->{urls} );
   for (@urls)
   {
      my $file_code = $1 if $_ =~ /\/(\w{12})/;
      next if !$file_code;
      my $file = $db->SelectRow( "SELECT * FROM Files WHERE file_code=?", $file_code );
      next if !$file;
      XUtils::AddToReports($ses, $file);
   }
   my $text = "Your report was accepted.";
   $text .= "<br>The files will be completely removed in $c->{dmca_expire} hours, or after manual approve."
     if $c->{dmca_expire};
   return $ses->redirect_msg( "$c->{site_url}/?op=mass_dmca", $text );
}

1;
