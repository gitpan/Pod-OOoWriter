use Test;
BEGIN { plan tests => 5 }

use Pod::OOoWriter;
my $tag = [ name => { attr1 => 'value1', attr2 => 'value2', attr3 => 'with & and <>' }];
$_ = Pod::OOoWriter::opening_tag($tag);

ok(Pod::OOoWriter::closing_tag($tag) eq '</name>');
ok(/^<name/);
ok(/attr1="value1"/);
ok(/attr2="value2"/);
ok(/attr3="with &amp; and &lt;&gt;"/);
