use utf8;
package Family::Site::Schema::Result::Cookbook;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Family::Site::Schema::Result::Cookbook

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=cut

=head1 TABLE: C<cookbook>

=cut

__PACKAGE__->table("cookbook");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 title

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 90

=head2 user

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=head2 type

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=head2 note

  data_type: 'varchar'
  is_nullable: 1
  size: 90

=head2 ingredients

  data_type: 'text'
  is_nullable: 0

=head2 instructions

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "title",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 90 },
  "user",
  { data_type => "varchar", is_nullable => 1, size => 20 },
  "type",
  { data_type => "varchar", is_nullable => 1, size => 20 },
  "note",
  { data_type => "varchar", is_nullable => 1, size => 90 },
  "ingredients",
  { data_type => "text", is_nullable => 0 },
  "instructions",
  { data_type => "text", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07045 @ 2016-01-28 19:46:39
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:EnOW7sVhYZMqCJDMPyekxQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
