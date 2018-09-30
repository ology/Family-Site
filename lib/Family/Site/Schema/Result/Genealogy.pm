use utf8;
package Family::Site::Schema::Result::Genealogy;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Family::Site::Schema::Result::Genealogy

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<genealogy>

=cut

__PACKAGE__->table("genealogy");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 100

=head2 parent

  data_type: 'varchar'
  is_nullable: 1
  size: 100

=head2 spouse

  data_type: 'varchar'
  is_nullable: 1
  size: 100


=head2 date

  data_type: 'varchar'
  is_nullable: 1
  size: 50

=cut


__PACKAGE__->add_columns(
  "id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "name",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 100 },
  "parent",
  { data_type => "varchar", is_nullable => 1, size => 100 },
  "spouse",
  { data_type => "varchar", is_nullable => 1, size => 100 },
  "date",
  { data_type => "varchar", is_nullable => 1, size => 50 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

__PACKAGE__->add_unique_constraint([ "name" ]);

# Created by DBIx::Class::Schema::Loader v0.07045 @ 2016-01-28 19:46:39
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:EnOW7sVhYZMqCJDMPyekxQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
