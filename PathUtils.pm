package Engine::Extras::PathUtils;
use strict;

sub normalize_path
{
   my ($path) = @_;
   $path =~ s/\/+/\//g;
   return $path;
}

sub joinpath
{
   my (@chunks) = @_;
   my $path = join('/', @chunks);
   $path =~ s/\/+/\//g;
   $path =~ s/\/+$//; # Explicitly add if needed
   return $path;
}

sub basename
{
   my ($path) = @_;
   my @chunks = grep { $_ } split(/\/+/, $path);

   return $chunks[$#chunks];
}

sub dirpath
{
   my ($path) = @_;
   my @chunks = grep { $_ } split(/\/+/, $path);
   return '/' . join('/', @chunks[0 .. $#chunks-1]);
}

1;
