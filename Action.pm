package Engine::Core::Action;
use strict;

use Exporter;
@Engine::Core::Action::ISA    = qw(Exporter);
@Engine::Core::Action::EXPORT = qw($ses $db $f IMPLEMENTS ANTICSRF_WHITELIST);

sub import
{
   my ($pkg, %args) = @_;

   my $caller = caller();
   eval "\$$caller\::IMPLEMENTS = \$args{IMPLEMENTS};";
   eval "\$$caller\::ANTICSRF_WHITELIST = \$args{ANTICSRF_WHITELIST};";

   my $is_exp = $pkg->isa('Exporter');
   $Exporter::ExportLevel++ if $is_exp;
   $pkg->SUPER::import();
   $Exporter::ExportLevel-- if $is_exp;
}

sub IMPLEMENTS
{
   my ($class) = @_;
   eval("\$$class\::IMPLEMENTS");
}

sub ANTICSRF_WHITELIST
{
   my ($class) = @_;
   eval("\$$class\::ANTICSRF_WHITELIST");
}

1;
