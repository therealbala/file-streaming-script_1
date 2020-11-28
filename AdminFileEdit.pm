package Engine::Actions::AdminFileEdit;
use strict;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(save)] );
use base 'Engine::Actions::FileEdit';

sub main { Engine::Actions::FileEdit::main() }
sub save { Engine::Actions::FileEdit::save() }

1;
