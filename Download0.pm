package Engine::Actions::Download0;
use strict;

use XFileConfig;
use Engine::Core::Action;

sub main
{
   my ($file) = @_;
   if ( $c->{pre_download_page_alt} )
   {
      my @arr = split( /,/, $c->{payment_plans} );
      $file->{free_download} = 1;
      use Data::Dumper qw(Dumper);
      my @payment_types = $ses->getPlugins('Payments')->get_payment_buy_with;

      my @plans = @{ $ses->ParsePlans( $c->{payment_plans}, 'array' ) };
      for (@plans)
      {
         $_->{payment_types} = \@payment_types;
      }

      my @traffic_packages = @{ $ses->ParsePlans( $c->{traffic_plans}, 'array' ) };
      for ( @plans, @traffic_packages )
      {
         $_->{payment_types} = \@payment_types;
      }

      return $ses->PrintTemplate(
         "download0_alt.html",
         %{$file},
         %{$c},
         'plans' => \@plans,
         'rand'  => $ses->randchar(6),

         #%cc,
         'referer'          => $f->{referer},
         'currency_symbol'  => $c->{currency_symbol} || '$',
         'ask_email'        => $ses->{utype} eq 'anon' && !$c->{no_anon_payments},
         'traffic_packages' => \@traffic_packages,
         'token_payments'   => $ses->genToken(op => 'payments'),
      );
   }

   print "Strict-Transport-Security: max-age=0;includeSubDomains;\n";

   my $limits = XUtils::GetPremiumComparison();
   return $ses->PrintTemplate( "download0.html", %{$file}, %{$limits}, 'referer' => $f->{referer} );
}

1;
