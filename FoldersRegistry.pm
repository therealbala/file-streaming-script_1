package Engine::Components::FoldersRegistry;
use strict;
use vars qw($ses $db $c $f);

sub findChildren
{
   my ($self, $fld) = @_;
   die("fld_id is undefined or zero") if !$fld->{fld_id};
   return ($fld, map { $self->findChildren($_) } @{ $db->SelectARef("SELECT * FROM Folders WHERE fld_parent_id=?", $fld->{fld_id}) });
}

1;
