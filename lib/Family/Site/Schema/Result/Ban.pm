use utf8;
package Family::Site::Schema::Result::Ban;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Family::Site::Schema::Result::Ban

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

=head1 TABLE: C<ban>

=cut

__PACKAGE__->table("ban");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 ip

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 15

=head2 last_seen

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
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
  "ip",
  {
    data_type => "varchar",
    default_value => "",
    is_nullable => 0, size => 15,
  },
  "last_seen",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

# Created by DBIx::Class::Schema::Loader v0.07045 @ 2016-01-28 19:46:39
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:SK2OliP4p5DOIJsf40H2yQ

# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
