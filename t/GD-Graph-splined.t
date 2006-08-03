use Test::More tests => 7;
our $VERSION = 2;

use lib "../lib";
BEGIN {
	use_ok('GD::Graph') ;
	use_ok('GD::Polyline');
	use_ok('GD::Graph::splined' => 0.021 );
};

use strict;
use warnings;

my $graph = GD::Graph::splined->new( 300, 300 );
isa_ok($graph, 'GD::Graph::splined');

eval { $graph->plot([
	["1st","2nd","3rd","4th","5th","6th","7th", "8th", "9th"],
	[    5,   12,   2,   133,   19,undef,    6,    15,    21],
	[    1,    2,    5,    6,    3,  1.5,    1,     3,     4]
])};
is($@, '', 'POD example');

eval { $graph->plot([	["1st"], [ 5 ], ])};
isnt($@, '', 'Barf') or diag "###[ $@ ]###";

eval { $graph->plot([	["1st","2nd"], [ 5, 7 ], ])};
is($@, '', 'Two') or diag "###[ $@ ]###";

__END__

if (1==2){
	open (NEWFILE, ">temp.png") or die $!;
	binmode NEWFILE;
	print NEWFILE $graph->{graph}->png;
	close(NEWFILE);
}
