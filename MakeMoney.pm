package Engine::Actions::MakeMoney;
use strict;

use XFileConfig;
use Engine::Core::Action;

sub main
{
   my @sizes = map { { t1 => $_ } } split( /\|/, $c->{tier_sizes} );
   $sizes[$_]->{t2} = $sizes[ $_ + 1 ]->{t1} for ( 0 .. $#sizes - 1 );
   $sizes[$#sizes]->{t2} = '*' if @sizes;

   my @tier1 = map { { amount => $_ } } split( /\|/, $c->{tier1_money} );
   my @tier2 = map { { amount => $_ } } split( /\|/, $c->{tier2_money} );
   my @tier3 = map { { amount => $_ } } split( /\|/, $c->{tier3_money} );
   my @tier4 = map { { amount => $_ } } split( /\|/, $c->{tier4_money} );

   require XCountries;

   my @countries1 = grep { $_ } map { $XCountries::iso_to_country->{ uc $_ } } split( /\|/, $c->{tier1_countries} );
   my @countries2 = grep { $_ } map { $XCountries::iso_to_country->{ uc $_ } } split( /\|/, $c->{tier2_countries} );
   my @countries3 = grep { $_ } map { $XCountries::iso_to_country->{ uc $_ } } split( /\|/, $c->{tier3_countries} );
   my @countries4 = grep { $_ } map { $XCountries::iso_to_country->{ uc $_ } } split( /\|/, $c->{tier4_countries} );

   $ses->PrintTemplate(
      "make_money.html",
      sizes             => \@sizes,
      tier1             => \@tier1,
      tier2             => \@tier2,
      tier3             => \@tier3,
      tier4             => \@tier4,
      countries1        => join( ', ', @countries1 ),
      countries2        => join( ', ', @countries2 ),
      countries3        => join( ', ', @countries3 ),
      countries4        => join( ', ', @countries4 ),
      tier_views_number => $c->{tier_views_number}||1000,
   );
}

1;
