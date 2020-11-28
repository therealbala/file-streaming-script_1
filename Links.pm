package Engine::Actions::Links;
use strict;

use XFileConfig;
use Engine::Core::Action;

sub main
{
   my @links;
   my @chunks = split(/\|/, $c->{external_links});

   while(my($url, $name) = splice(@chunks, 0, 2))
   {
      $url = "http://$url" unless $url =~ /^https?:\/\//i;
      push @links, { url => $url, name => $name };
   }

   $ses->PrintTemplate( 'links.html', links => \@links );
}

1;
