package Engine::Core::Cronjob;
use strict;

use Exporter;
@Engine::Core::Cronjob::ISA    = qw(Exporter);
@Engine::Core::Cronjob::EXPORT = qw($ses $db);

our $ses = $main::ses;
our $db = $main::db;

1;
