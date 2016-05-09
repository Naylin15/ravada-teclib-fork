use warnings;
use strict;

use IPC::Run3;
use POSIX ":sys_wait_h";
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Domain::KVM');

my $test = Test::SQL::Data->new( config => 't/etc/ravada.conf');
my $ravada = Ravada->new( connector => $test->connector);

my ($DOMAIN_NAME) = $0 =~ m{.*/(.*)\.};
my $DOMAIN_NAME_SON=$DOMAIN_NAME."_son";


sub test_vm_kvm {
    my $vm = $ravada->vm->[0];
    ok($vm,"No vm found") or exit;
    ok(ref($vm) =~ /KVM$/,"vm is no kvm ".ref($vm)) or exit;

    ok($vm->type, "Not defined $vm->type") or exit;
    ok($vm->host, "Not defined $vm->host") or exit;

}
sub test_remove_domain {
    my $name = shift;

    my $domain;
    $domain = $ravada->search_domain($name);

    if ($domain) {
        diag("Removing domain $name");
        eval { $domain->remove() };
        ok(!$@ , "Error removing domain $name : $@") or exit;

        ok(! -e $domain->file_base_img ,"Image file was not removed "
                    . $domain->file_base_img )
                if  $domain->file_base_img;

    }
    $domain = $ravada->search_domain($name);
    ok(!$domain, "I can't remove old domain $name") or exit;


}

sub test_new_domain_from_iso {
    my $name = $DOMAIN_NAME;

    test_remove_domain($name);

    diag("Creating new domain $name from iso");
    my $domain;
    eval { $domain = $ravada->create_domain(name => $name, id_iso => 1) };
    ok(!$@,"Domain $name not created: $@");

    ok($domain,"Domain not created") or return;
    my $exp_ref= 'Ravada::Domain::KVM';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
        if $domain;

    my @cmd = ('virsh','desc',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");

    my $sth = $test->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($domain->name);
    my $row =  $sth->fetchrow_hashref;
    ok($row->{name} && $row->{name} eq $domain->name,"I can't find the domain at the db");
    $sth->finish;

    return $domain;
}

sub test_prepare_base {
    my $domain = shift;
    $domain->prepare_base();

    my $sth = $test->dbh->prepare("SELECT * FROM domains WHERE name=? AND is_base='y'");
    $sth->execute($domain->name);
    my $row =  $sth->fetchrow_hashref;
    ok($row->{name} && $row->{name} eq $domain->name);
    $sth->finish;
}

sub test_new_domain_from_base {
    my $base = shift;

    my $name = $DOMAIN_NAME_SON;
    test_remove_domain($name);

    diag("Creating domain $name from base ");
    my $domain = $ravada->create_domain(name => $name, id_base => $base->id);
    ok($domain,"Domain not created");
    my $exp_ref= 'Ravada::Domain::KVM';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
        if $domain;

    my @cmd = ('virsh','desc',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");

    my $sth = $test->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($domain->name);
    my $row =  $sth->fetchrow_hashref;
    ok($row->{name} && $row->{name} eq $domain->name,"I can't find the domain at the db");
    $sth->finish;

    SKIP: {
        #TODO: that could be done
        skip("No remote-viewer",1) if 1 || ! -e "/usr/bin/remote-viewer";
        test_spawn_viewer($domain);
    }

    return $domain;

}

sub test_spawn_viewer {
    my $domain = shift;

    my $pid = fork();
    die "Cannot fork"   if !defined $pid;

    if ($pid == 0) {

        my $uri = $domain->display;

        my @cmd = ('remote-viewer',$uri);
        my ($in,$out,$err);
        run3(\@cmd,\$in,\$out,\$err);
        ok(!$?,"Error $? running @cmd");
    } else {
        sleep 5;
        $domain->domain->shutdown;
        sleep 5;
        $domain->domain->destroy;
        exit;
    }
    waitpid(-1, WNOHANG);
}

sub remove_old_volumes {

    my $name = "$DOMAIN_NAME_SON.qcow2";
    my $file = "/var/lib/libvirt/images/$name";
    remove_volume($file);

    remove_volume("/var/lib/libvirt/images/$DOMAIN_NAME.img");
}

sub remove_volume {
    my $file = shift;

    return if !-e $file;
    diag("removing old $file");
    $ravada->remove_volume($file);
    ok(! -e $file,"file $file not removed" );
}

################################################################

test_vm_kvm();
test_remove_domain($DOMAIN_NAME_SON);
remove_old_volumes();
my $domain = test_new_domain_from_iso();


if (ok($domain,"test domain not created")) {
    test_prepare_base($domain);

    my $domain_son = test_new_domain_from_base($domain);
    test_remove_domain($domain_son->name);
    test_remove_domain($domain->name);
}

done_testing();
