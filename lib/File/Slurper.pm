package File::Slurper;

use strict;
use warnings;

use Carp 'croak';
use Exporter 5.57 'import';
use File::Spec::Functions 'catfile';
our @EXPORT_OK = qw/read_binary read_text read_lines write_binary write_text read_dir/;

sub read_binary {
	my $filename = shift;

	# This logic is a bit ugly, but gives a significant speed boost
	# because slurpy readline is not optimized for non-buffered usage
	open my $fh, '<:unix', $filename or croak "Couldn't open $filename: $!";
	if (my $size = -s $fh) {
		my $buf;
		my ($pos, $read) = 0;
		do {
			defined($read = read $fh, ${$buf}, $size - $pos, $pos) or croak "Couldn't read $filename: $!";
			$pos += $read;
		} while ($read && $pos < $size);
		return ${$buf};
	}
	else {
		return do { local $/; <$fh> };
	}
}

my $crlf_default = $^O eq 'MSWin32' ? 1 : 0;
my $has_utf8_strict = eval { require PerlIO::utf8_strict };

sub _text_layers {
	my ($encoding, $crlf) = @_;
	$crlf = $crlf_default if $crlf && $crlf eq 'auto';

	if ($encoding =~ /^(latin|iso-8859-)1$/i) {
		return $crlf ? ':unix:crlf' : ':raw';
	}
	elsif ($has_utf8_strict && $encoding =~ /^utf-?8\b/i) {
		return $crlf ? ':unix:utf8_strict:crlf' : ':unix:utf8_strict';
	}
	else {
		# non-ascii compatible encodings such as UTF-16 need encoding before crlf
		return $crlf ? ":raw:encoding($encoding):crlf" : ":raw:encoding($encoding)";
	}
}

sub read_text {
	my ($filename, $encoding, $crlf) = @_;
	$encoding ||= 'utf-8';
	my $layer = _text_layers($encoding, $crlf);
	return read_binary($filename) if $layer eq ':raw';

	open my $fh, "<$layer", $filename or croak "Couldn't open $filename: $!";
	return do { local $/; <$fh> };
}

sub write_text {
	my ($filename, undef, $encoding, $crlf) = @_;
	$encoding ||= 'utf-8';
	my $layer = _text_layers($encoding, $crlf);

	open my $fh, ">$layer", $filename or croak "Couldn't open $filename: $!";
	print $fh $_[1] or croak "Couldn't write to $filename: $!";
	close $fh or croak "Couldn't write to $filename: $!";
	return;
}

sub write_binary {
	return write_text(@_[0,1], 'latin-1');
}

sub read_lines {
	my ($filename, $encoding, %options) = @_;
	$encoding ||= 'utf-8';
	my $layer = _text_layers($encoding, $options{crlf});

	open my $fh, "<$layer", $filename or croak "Couldn't open $filename: $!";
	return <$fh> if not %options;
	my @buf = <$fh>;
	close $fh;
	chomp @buf if $options{chomp};
	return @buf;
}

sub read_dir {
	my ($dirname) = @_;
	opendir my ($dir), $dirname or croak "Could not open $dirname: $!";
	return grep { not m/ \A \.\.? \z /x } readdir $dir;
}

1;

# ABSTRACT: A simple, sane and efficient module to slurp a file

=head1 SYNOPSIS

 use File::Slurper 'read_text';
 my $content = read_text($filename);

=head1 DESCRIPTION

B<DISCLAIMER>: this module is experimental, and may still change in non-compatible ways.

This module provides functions for fast and correct slurping and spewing. All functions are optionally exported.

=func read_text($filename, $encoding, $crlf)

Reads file C<$filename> into a scalar and decodes it from C<$encoding> (which defaults to UTF-8). If C<$crlf> is true, crlf translation is performed. The default for this argument is off. The special value C<'auto'> will set it to a platform specific default value.

=func read_binary($filename)

Reads file C<$filename> into a scalar without any decoding or transformation.

=func read_lines($filename, $encoding, %options)

Reads file C<$filename> into a list/array after decoding from C<$encoding>. By default it returns this list. Can optionally take this named argument:

=over 4

=item * chomp

C<chomp> the lines.

=back

=func write_text($filename, $content, $encoding, $crlf)

Writes C<$content> to file C<$filename>, encoding it to C<$encoding> (which defaults to UTF-8). It can also take a C<crlf> argument that works exactly as in read_text.

=func write_binary($filename, $content)

Writes C<$content> to file C<$filename> as binary data.

=func read_dir($dirname)

Open C<dirname> and return all entries except C<.> and C<..>.

=head1 TODO

=over 4

=item * C<open_text>?

=back

=head1 RATIONALE

This module tries to make it as easy as possible to read and write files correctly and fast. The most correct way of doing this is not always obvious (e.g. L<#83126|https://rt.cpan.org/Public/Bug/Display.html?id=83126>), and just as often the most obvious correct way is not the fastest correct way. This module hides away all such complications behind an easy intuitive interface.

=head1 DEPENDENCIES

This module has an optional dependency on PerlIO::utf8_strict. Installing this will make UTF-8 encoded IO significantly faster, but should not otherwise affect the operation of this module. This may change into a dependency on the related Unicode::UTF8 in the future.

=head1 SEE ALSO

=over 4

=item * L<Path::Tiny|Path::Tiny>

A minimalistic abstraction not only around IO but also paths.

=item * L<IO::All|IO::All>

An attempt to expose as many IO related features as possible via a single API.

=back

=cut
