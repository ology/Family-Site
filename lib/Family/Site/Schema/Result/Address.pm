use utf8;
package Family::Site::Schema::Result::Address;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Family::Site::Schema::Result::Address

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<address>

=cut

__PACKAGE__->table("address");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 first_name

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 20

=head2 last_name

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=head2 street

  data_type: 'varchar'
  is_nullable: 1
  size: 50

=head2 city

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=head2 state

  data_type: 'varchar'
  is_nullable: 1
  size: 2

=head2 zip

  data_type: 'varchar'
  is_nullable: 1
  size: 10

=head2 phone

  data_type: 'varchar'
  is_nullable: 1
  size: 15

=head2 phone2

  data_type: 'varchar'
  is_nullable: 1
  size: 15

=head2 birthday

  data_type: 'date'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 email

  data_type: 'varchar'
  is_nullable: 1
  size: 50

=head2 notes

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "first_name",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 20 },
  "last_name",
  { data_type => "varchar", is_nullable => 1, size => 20 },
  "street",
  { data_type => "varchar", is_nullable => 1, size => 50 },
  "city",
  { data_type => "varchar", is_nullable => 1, size => 20 },
  "state",
  { data_type => "varchar", is_nullable => 1, size => 2 },
  "zip",
  { data_type => "varchar", is_nullable => 1, size => 10 },
  "phone",
  { data_type => "varchar", is_nullable => 1, size => 15 },
  "phone2",
  { data_type => "varchar", is_nullable => 1, size => 15 },
  "birthday",
  { data_type => "date", datetime_undef_if_invalid => 1, is_nullable => 1 },
  "email",
  { data_type => "varchar", is_nullable => 1, size => 50 },
  "notes",
  { data_type => "text", is_nullable => 1 },
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
