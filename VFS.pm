package Engine::Extras::VFS;
use strict;
use Data::Dumper;

### A filesystem-like interface for accessing XFS account files

sub new
{
   my ($class, $ses) = @_;

   my $self = {};
   $self->{ses} = $ses;
   $self->{db} = $ses->db;

   bless $self, $class;
}

sub get_dir_by_path
{
   my ($self, $path) = @_;
   my @chunks = grep { $_ } split(/\/+/, $path);

   my $usr_id = $self->{ses}->getUserId;
   my $folder;

   for(@chunks)
   {
      $folder = $self->{db}->SelectRow("SELECT * FROM Folders
         WHERE usr_id=? AND fld_name=? AND fld_parent_id=?",
         $usr_id, $_, $folder ? $folder->{fld_id} : 0);
      return if !$folder;
   }

   $folder->{path} = $path if $folder;

   return $folder;
}

sub get_file_by_path
{
   my ($self, $path) = @_;
   die("Not a file path: $path") if $path =~ /\/$/;

   my $dirpath = _dirpath($path);
   my $dir = $self->get_dir_by_path($dirpath);
   return undef if !$dir && $dirpath ne '/';

   my $file = $self->{db}->SelectRow("SELECT * FROM Files WHERE usr_id=? AND file_fld_id=? AND file_name=? ORDER BY file_created DESC",
      $self->{ses}->getUserId,
      $dir ? $dir->{fld_id} : 0,
      _basename($path));

   $file->{path} = $path if $file;
   return $file;
}

sub delete
{
   my ($self, $path) = @_;

   my $file = $self->get_file_by_path($path) if $path !~ /\/$/;
   my $dir = $self->get_dir_by_path($path);
   die("Can't delete '/'") if _normalize_path($path) eq '/';
   die("Object not exists: $path") if !$file && !$dir;
   return $self->{ses}->DeleteFile($file) if $file;

   my $files = $self->{db}->SelectOne("SELECT COUNT(*) FROM Files WHERE file_fld_id=?", $dir->{fld_id});
   my $folders = $self->{db}->SelectOne("SELECT COUNT(*) FROM Folders WHERE fld_parent_id=?", $dir->{fld_id});
   die("Directory is not empty: $path") if $files || $folders;

   $self->{db}->Exec("DELETE FROM Folders WHERE fld_id=?", $dir->{fld_id});
}

sub mkdir
{
   my ($self, $path) = @_;

   die("Directory already exists: $path") if $self->get_dir_by_path($path);

   my $dirpath = _dirpath($path);
   my $dir = $self->get_dir_by_path($dirpath);
   die("Directory not exists: $dirpath") if !$dir && $dirpath ne '/';

   $self->{db}->Exec( "INSERT INTO Folders SET usr_id=?, fld_parent_id=?, fld_name=?",
      $self->{ses}->getUserId, $dir ? $dir->{fld_id} : 0, _basename($path));
}

sub rmdir
{
   my ($self, $path) = @_;
   die("Can't remove '/'") if _normalize_path($path) eq '/';

   my $dir = $self->get_dir_by_path($path);
   die("Directory not exists: $path") if !$dir;

   my ($subfolders, $files) = $self->list($path, depth => 'infinity');
   $self->{ses}->DeleteFilesMass($files) if $files;
   $self->{db}->Exec("DELETE FROM Folders WHERE fld_id=?", $_->{fld_id}) for @$subfolders;
   $self->{db}->Exec("DELETE FROM Folders WHERE fld_id=?", $dir->{fld_id});
}

sub exists
{
   my ($self, $path) = @_;
   return 1 if _normalize_path($path) eq '/';

   my $file = $self->get_file_by_path($path) if $path !~ /\/$/;
   my $dir = $self->get_dir_by_path($path);

   return 1 if $file || $dir;
}

sub list
{
   my ($self, $path, %opts) = @_;

   my $file = $self->get_file_by_path($path) if $path !~ /\/$/;
   return ([], [$file]) if $file;

   my @folders;
   my $dir = $self->get_dir_by_path($path);

   if($opts{include_self})
   {
      push @folders, $dir ? $dir : {
         path => '/',
         fld_created => $self->{db}->SelectOne("SELECT MAX(file_created) FROM Files WHERE usr_id=?", $self->{ses}->getUserId),
      };
   }

   return (\@folders, []) if defined($opts{depth}) && $opts{depth} <= 0 && $opts{depth} ne 'infinity';

   my $depth = $opts{depth} || 1;
   die("No such path: '$path'") if !$dir && _normalize_path($path) ne '/';
   die("Invalid depth value: $depth") if $depth !~ /^([0-9+]|infinity)$/;

   my $fld_id = $dir ? $dir->{fld_id} : 0;

   my $files = $self->{db}->SelectARef("SELECT * FROM Files WHERE usr_id=? AND file_fld_id=? ORDER BY file_name",
      $self->{ses}->getUserId, $fld_id);

   my $subfolders = $self->{db}->SelectARef("SELECT * FROM Folders WHERE usr_id=? AND fld_parent_id=? ORDER BY fld_name",
      $self->{ses}->getUserId, $fld_id);
   
   $_->{path} = _joinpath($path, $_->{fld_name}) . '/' for @$subfolders;
   $_->{path} = _joinpath($path, $_->{file_name}) for @$files;

   my $cnt = int(@$subfolders);
   my $next_depth = $depth eq 'infinity' ? $depth : $depth - 1;
   
   for(my $i = 0; $i < $cnt; $i++)
   {
      my ($c_folders, $c_files) = $self->list($subfolders->[$i]->{path}, depth => $next_depth);
      push @$subfolders, @$c_folders;
      push @$files, @$c_files;
   }

   push @folders, @$subfolders;
   return \@folders, $files;
}

sub move
{
   my ($self, $path, $newpath) = @_;

   my $file = $self->get_file_by_path($path) if $path !~ /\/$/;
   my $dir = $self->get_dir_by_path($path);
   die("Can't move '/'") if _normalize_path($path) eq '/';
   die("Object not exists: $path") if !$file && !$dir;

   my $newdir = $self->get_dir_by_path($newpath);
   my $newname = $file ? $file->{file_name} : $dir->{fld_name};

   if(!$newdir && $newpath !~ /\/$/)
   {
      $newdir = $self->get_dir_by_path(_dirpath($newpath));
      $newname = _basename($newpath);
   }

   die("Directory not exists: $newpath") if !$newdir && _dirpath($newpath) !~ /^\/?$/;
   die("Invalid name: $newname") if $newname eq '';

   my $fld_id_to = $newdir ? $newdir->{fld_id} : 0;
   return $self->{db}->Exec("UPDATE Files SET file_fld_id=?, file_name=? WHERE file_id=?", $fld_id_to, $newname, $file->{file_id}) if $file;
   return $self->{db}->Exec("UPDATE Folders SET fld_parent_id=?, fld_name=? WHERE fld_id=?", $fld_id_to, $newname, $dir->{fld_id}) if $dir;
}

sub _normalize_path
{
   my ($path) = @_;
   $path =~ s/\/+/\//g;
   return $path;
}

sub _joinpath
{
   my (@chunks) = @_;
   my $path = join('/', @chunks);
   $path =~ s/\/+/\//g;
   $path =~ s/\/+$//; # Explicitly add it if needed
   return $path;
}

sub _basename
{
   my ($path) = @_;
   my @chunks = grep { $_ } split(/\/+/, $path);

   return $chunks[$#chunks];
}

sub _dirpath
{
   my ($path) = @_;
   my @chunks = grep { $_ } split(/\/+/, $path);
   return '/' . join('/', @chunks[0 .. $#chunks-1]);
}

1;
