package Pod::OOoWriter::XMLParser;
use strict;

# $Id: XMLParser.pm,v 1.17 2004/06/09 14:32:32 cbouvi Exp $
#
#  Copyright © 2004 Cédric Bouvier
#
#  This library is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License as published by the Free
#  Software Foundation; either version 2 of the License, or (at your option)
#  any later version.
#
#  This library is distributed in the hope that it will be useful, but WITHOUT
#  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
#  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
#  more details.
#
#  You should have received a copy of the GNU General Public License along with
#  this library; if not, write to the Free Software Foundation, Inc., 59 Temple
#  Place, Suite 330, Boston, MA  02111-1307  USA

# $Log: XMLParser.pm,v $
# Revision 1.17  2004/06/09 14:32:32  cbouvi
# Added comments
#
# Revision 1.16  2004/06/09 13:54:26  cbouvi
# Start handler now gives up as soon as possible (if before the head)
#
# Revision 1.15  2004/06/08 15:38:41  cbouvi
# Added support for numbered list. Code cleanup
#
# Revision 1.14  2004/06/08 14:53:36  cbouvi
# Removed some sanity checks, useless with the new more generic parser
#
# Revision 1.13  2004/06/08 14:04:23  cbouvi
# More generic generation of XML tags (less hard-coded)
#
# Revision 1.12  2004/06/04 15:12:05  cbouvi
# Added synonyms ul[123] for over[456] (still needs to come up with something for
# ordered lists).
#
# Revision 1.11  2004/06/04 14:35:10  cbouvi
# Better handling of lists. Applies the style at list level as well as item level
#
# Revision 1.10  2004/06/04 13:16:03  cbouvi
# Correct subclassing of XML::Parser (it worked, but I don't know how)
#
# Revision 1.9  2004/06/03 13:58:43  cbouvi
# Changed the license notice (s/program/library/)
#
# Revision 1.8  2004/06/03 11:23:38  cbouvi
# Added comments
#
# Revision 1.7  2004/05/14 11:37:17  cbouvi
# Added #para# marker
#
# Revision 1.6  2004/05/13 13:09:55  cbouvi
# Added basic support for ##keyword## substitution
#
# Revision 1.5  2004/05/12 12:15:19  cbouvi
# Added more POD commands. Prevented recognition of patterns with the TOC
#
# Revision 1.4  2004/05/12 11:29:27  cbouvi
# Proper handling of latin1->utf8 conversion and XML entities
#
# Revision 1.3  2004/05/12 09:09:33  cbouvi
# Added (limited) support for =over
#
# Revision 1.2  2004/05/11 13:14:36  cbouvi
# Full handling of XML template (before and after contents)
#

use XML::Parser;
use vars qw/ @ISA /;
@ISA = qw/ XML::Parser /;

# These tokens (keys) are looked for in the template.sxw
# the values are arrayrefs, consisting of:
# - a string: this will serve as a key to store tags in attribute ooo_tokens
# - a list of integers (defaults to (1)): the reverse depths at which the tags
#   must be read and associated with the token. By default, only the containing
#   tag is important, <text:p> for a paragraph, or <text:h> for a heading.
#   However, list tokens appear inside a <text:p>, which is inside a
#   <text:list-item>, which is inside a <text:unordered-list>. (1, 2, 3) will
#   memorize all three tags.
my %tokens = (
    '#bold#'     => [ 'B' ],
    '#italic#'   => [ 'I' ],
    '#file#'     => [ 'F' ],
    '#code#'     => [ 'C' ],
    '#verbatim#' => [ 'verbatim' ],
    '#head1#'    => [ 'head1' ],
    '#head2#'    => [ 'head2' ],
    '#head3#'    => [ 'head3' ],
    '#head4#'    => [ 'head4' ],

    '#over4#'    => [ 'ul1', 1, 2, 3 ],
    '#over5#'    => [ 'ul2', 1, 2, 3 ],
    '#over6#'    => [ 'ul3', 1, 2, 3 ],

    '#ol1#'      => [ 'ol1', 1, 2, 3 ],
    '#ol2#'      => [ 'ol2', 1, 2, 3 ],
    '#ol3#'      => [ 'ol3', 1, 2, 3 ],

    '#ul1#'      => [ 'ul1', 1, 2, 3 ],
    '#ul2#'      => [ 'ul2', 1, 2, 3 ],
    '#ul3#'      => [ 'ul3', 1, 2, 3],

    '#para#'     => [ 'para' ],
);

# Constructor: set up the event handlers and initialize some attributes
sub new {

    my $self = XML::Parser::new @_;
    
    # Handlers are set as closures, containing $self. This lets them access the
    # parser's methods and attributes, not only the Expat object's.
    $self->setHandlers(
        Start   => sub { $self->ooo_start_hdl(@_) },
        End     => sub { $self->ooo_end_hdl(@_) },
        Char    => sub { $self->ooo_char_hdl(@_) },
        Default => sub { $self->ooo_default_hdl(@_) },
    );

    # our internal attributes will be prefixed with 'ooo_' so as not to overlap
    # with our ancestor's
    # ooo_depth: the depth within the XML tree
    # ooo_foot_found and ooo_head_found: flags indicating whether the start or
    # end was found
    $self->{ooo_depth} = $self->{ooo_foot_found} = $self->{ooo_head_found} = 0;
    $self->{ooo_headers} = []; # array for the start of document (until #head1#)
    $self->{ooo_footers} = []; # array for the end of document (after the last sibling to #head1#)
    $self->{ooo_elem_stack} = []; # stack of XML elements with their attributes
    $self->{ooo_tokens}  = {}; # arrayrefs of XML elements with their attributes, associated with tokens.
    return $self;
}

sub ooo_default_hdl {

    my ($self, $parser, $string) = @_;

    # before the head, and after the foot, store the original string for
    # verbatim copy later on.
    push @{$self->{ooo_headers}}, $parser->original_string() unless $self->{ooo_head_found};
    push @{$self->{ooo_footers}}, $parser->original_string() if $self->{ooo_foot_found};
}

sub ooo_start_hdl {

    my ($self, $parser, $elem, %attr) = @_;

    # before the head, store the original string for verbatim copy later on.
    push @{$self->{ooo_headers}}, $parser->original_string() unless $self->{ooo_head_found};

    # after the foot, store the original string for verbatim copy later on.
    # the rest is irrelevant after the foot
    if ( $self->{ooo_foot_found} ) {
        push @{$self->{ooo_footers}}, $parser->original_string();
        return;
    }

    # memorize the current elem, in case a token is recognized inside
    push @{$self->{ooo_elem_stack}}, [ $elem, \%attr ];

    $self->{ooo_depth}++;

    # Tokens within a table of contents should be ignored
    $self->{ooo_in_toc} = 1 if $elem eq 'text:table-of-content';

}

sub ooo_end_hdl {

    my ($self, $parser, $elem) = @_;

    pop @{$self->{ooo_elem_stack}};
    $self->{ooo_depth}--;
    $self->{ooo_in_toc} = 0 if $elem eq 'text:table-of-content';

    if ( ! $self->{ooo_head_found} ) {
        # verbatim copy when before the first #head1# token
        push @{$self->{ooo_headers}}, $parser->original_string();
    }
    else {
        if ( ! $self->{ooo_foot_found} and $self->{ooo_depth} < $self->{ooo_content_depth} - 1 ) {
            # We're back to one level less deep than the starting of the text
            # body: the footer starts here
            $self->{ooo_foot_found} = 1;
        }
    }
    if ( $self->{ooo_foot_found} ) {
        # verbatim copy after the end of the text body
        push @{$self->{ooo_footers}}, $parser->original_string();
    }
}

#
# memorise_parent_tags
#
# Memorizes the tags that contain a given token. How deep to memorize is given
# by the list of depths in %tokens. By default, memorize only the immediately
# surrounding tag.
sub memorise_parent_tags {

    my ($self, $token) = @_;
    my ($directive, @depth) = @{$tokens{$token}};
    @depth = (1) unless @depth;
    $self->{ooo_tokens}{$directive} = [
        map $self->{ooo_elem_stack}[-$_], @depth
    ];
}

sub ooo_char_hdl {

    my ($self, $parser, $string) = @_;

    unless ( $self->{ooo_in_toc} ) {
        foreach ( keys %tokens ) {
            if ( $string =~ /$_/ ) {
                # Token recognized

                # Sanity checks

                if ( /#ol\d#/ ) {
                    my $e = $self->{ooo_elem_stack}[-3][0];
                    die "Token $_ found outside of a numbered list (<$e>)\n" unless $e eq 'text:ordered-list';
                }

                if ( /#(?:over|ul)\d#/ ) {
                    my $e = $self->{ooo_elem_stack}[-3][0];
                    die "Token $_ found outside of a bullet list (<$e>)\n" unless $e eq 'text:unordered-list';
                }

                if ( $_ eq '#head1#' ) {
                    # This is the starting of the text body
                    $self->{ooo_head_found} = 1;
                    $self->{ooo_content_depth} = $self->{ooo_depth};
                    pop @{$self->{ooo_headers}};
                }

                $self->memorise_parent_tags($_);
            }
        }
    }
    # before the head, and after the foot, store the original string for
    # verbatim copy later on.
    push @{$self->{ooo_headers}}, $parser->original_string() unless $self->{ooo_head_found};
    push @{$self->{ooo_footers}}, $parser->original_string() if $self->{ooo_foot_found};
}

1;
