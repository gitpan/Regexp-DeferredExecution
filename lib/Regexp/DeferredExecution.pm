package Regexp::DeferredExecution;

use strict;
use vars qw($VERSION);

$VERSION = '0.02';

use Text::Balanced qw( extract_multiple
		       extract_codeblock
		     );

use overload;

sub import {
    shift;
    overload::constant('qr' => \&convert);
}

sub unimport {
    shift;
    overload::remove_constant('qr');
}

sub convert {

    my $re = shift;

    return $re unless $re =~ m/\(\?\{/; # no need to alter this one.

    my @chunks =
	extract_multiple($re,
			 [ qr/\(\?   # '(?' (escaped)
			      (?=\{) # followed by '{' (lookahead)
			     /x,
			   \&extract_codeblock
			 ]
			);

    for (my $i = 1 ; $i < @chunks ; $i++) {
	# wrap all code into a closure and push onto the stack:
	if ($chunks[$i-1] eq "(?") {
	    $chunks[$i] =~ s/\A \{
                             (.*)
                             \} \Z
                            /{
  local \@Regexp::Deferred::c;
  push \@Regexp::Deferred::c, [\$^N, q{$1}];
}/msx;
	}
    }

    $re = join("", @chunks);

    # install the stack storage and execution code:
    $re = "(?{
  local \@Regexp::Deferred::c = ();
})$re(?{
  for (\@Regexp::Deferred::c) {
    \$^N = \$\$_[0];
    eval \$\$_[1];
  }
})";

    return $re;
}

1;
__END__

=pod

=head1 NAME

Regexp::Deferred - defer execution of C<(?{})> codeblock until end of match

=head1 SYNOPSIS

  use Regexp::Deferred;
  "foobar" =~
    /(?:foo (?{ warn "matched foo!" }) ) d
     |
     (?:bar (?{ warn "matched bar!"}) )
    /x;

  __END__
  matched bar!

=head1 DESCRIPTION

The Perl regular expression engine provides a special embedded
pattern, (?{ <code> }), that immediately executes <code> when the
pattern is used during the matching process.  In the L<SYNOPSIS>
example, the initial C<foo> pattern is initially matched by the
regular expression engine, and the associated code would normally be
executed immediately.  Regexp::Deferred overrides the C<qr> function
such that all of the code blocks get deferred until the very end of
the match, at which time only the blocks participating in the overall
successful match are executed.

That doesn't sound like much, but it does allow you to change this:

  if(m/ (fee) .* (fie) .* (foe) .* (fum) /x) {
      ($fee, $fie, $foe, $fum) = ($1, $2, $3, $4);
  }

into:

  use Regexp::DeferredExecution;
  m/ (fee) (?{ $fee = $^N }) .*
     (fie) (?{ $fie = $^N }) .*
     (foe) (?{ $foe = $^N }) .*
     (fum) (?{ $fum = $^N })
   /x;

Which means that adding new sets of capturing parentheses doesn't
require the counting exercise to figure out which set is $1, $2, etc.

Of course this mechanism isn't specific to assigning from $^N; there's
no doubt a bunch of other clever things you can do with this as well;
I'll let you know as I run into them.

=head1 USAGE

Like any other package that overload core functionality, you can turn
it on and off via "use" and "no" statements.

=head1 BUGS

Note that currently, only the currently active $^N matching variable
is stored for delayed access (e.g. don't try to access other special
regexp variables from within a C<(?{})> code block, because they might
not be as you'd expect).

None so far, but it's still early.

=head1 TODO

When closures can be compiled from within C<(?{})> constructs, all the
special variables will become available and this will all be much
simpler.

=head1 AUTHOR

Aaron J. Mackey <amackey@virginia.edu>

=head1 SEE ALSO

L<perlre>, L<Regexp::Fields>, L<Regexp::English>

=cut
