package Pod::OOoWriter::XMLParser;
use strict;

# $Id: XMLParser.pm,v 1.9 2004/06/03 13:58:43 cbouvi Exp $
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
# the values are used to index the styles stored in attribute ooo_tokens.
my %tokens = (
    '#bold#'     => 'B',
    '#italic#'   => 'I',
    '#file#'     => 'F',
    '#code#'     => 'C',
    '#verbatim#' => 'verbatim',
    '#head1#'    => 'head1',
    '#head2#'    => 'head2',
    '#head3#'    => 'head3',
    '#head4#'    => 'head4',
    '#over4#'    => 'over4',
    '#over5#'    => 'over5',
    '#over6#'    => 'over6',
    '#para#'     => 'para',
);

# Constructor: set up the event handlers and initialize some attributes
sub new {

    my $self = XML::Parser::new @_, Handlers => {
        Start   => \&ooo_start_hdl,
        End     => \&ooo_end_hdl,
        Char    => \&ooo_char_hdl,
        Default => \&ooo_default_hdl,
    };

    # our internal attributes will be prefixed with 'ooo_' so as not to overlap
    # with our ancestor's
    # ooo_depth: the depth within the XML tree
    # ooo_foot_found and ooo_head_found: flags indicating whether the start or
    # end was found
    $self->{ooo_depth} = $self->{ooo_foot_found} = $self->{ooo_head_found} = 0;
    $self->{ooo_headers} = []; # array for the start of document (until #head1#)
    $self->{ooo_footers} = []; # array for the end of document (after the last sibling to #head1#)
    $self->{ooo_tokens}  = {};
    return $self;
}

sub ooo_default_hdl {

    my ($self, $string) = @_;

    # before the head, and after the foot, store the original string for
    # verbatim copy later on.
    push @{$self->{ooo_headers}}, $self->original_string() unless $self->{ooo_head_found};
    push @{$self->{ooo_footers}}, $self->original_string() if $self->{ooo_foot_found};
}

sub ooo_start_hdl {

    my ($self, $elem, %attr) = @_;
    # memorize the current elem, in case a token is recognized inside
    $self->{ooo_current_elem} = $elem;
    $self->{ooo_current_attr} = \%attr;

    $self->{ooo_depth}++;

    # Tokens within a table of contents should be ignored
    $self->{ooo_in_toc} = 1 if $elem eq 'text:table-of-content';

    # before the head, and after the foot, store the original string for
    # verbatim copy later on.
    push @{$self->{ooo_headers}}, $self->original_string() unless $self->{ooo_head_found};
    push @{$self->{ooo_footers}}, $self->original_string() if $self->{ooo_foot_found};
}

sub ooo_end_hdl {

    my ($self, $elem) = @_;

    $self->{ooo_current_elem} = $self->{ooo_current_attr} = undef;
    $self->{ooo_depth}--;
    $self->{ooo_in_toc} = 0 if $elem eq 'text:table-of-content';

    if ( ! $self->{ooo_head_found} ) {
        # verbatim copy when before the first #head1# token
        push @{$self->{ooo_headers}}, $self->original_string();
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
        push @{$self->{ooo_footers}}, $self->original_string();
    }
}

sub ooo_char_hdl {

    my ($self, $string) = @_;

    unless ( $self->{ooo_in_toc} ) {
        foreach ( keys %tokens ) {
            if ( $string =~ /$_/ ) {
                # Token recognized
                if ( $_ eq '#head1#' ) {
                    # This is the starting of the text body
                    $self->{ooo_head_found} = 1;
                    $self->{ooo_content_depth} = $self->{ooo_depth};
                    pop @{$self->{ooo_headers}};
                }

                # Memorize the style attribute associated to the token
                $self->{ooo_tokens}{$tokens{$_}} = $self->{ooo_current_attr}{'text:style-name'};
                last;
            }
        }
    }
    # before the head, and after the foot, store the original string for
    # verbatim copy later on.
    push @{$self->{ooo_headers}}, $self->original_string() unless $self->{ooo_head_found};
    push @{$self->{ooo_footers}}, $self->original_string() if $self->{ooo_foot_found};
}

1;
