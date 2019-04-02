package PrettyPrintDirView2;
use strict;
use DBI;
use File::Basename;
use File::Path;

my $dbh;
my $fileSth;
my $fileCommitsSth;
my $fileAuthorsSth;
my $fileTokenCountsSth;
my $dirSth;
my $dirCommitsSth;
my $dirAuthorsSth;
my $dirTokenCountsSth;

my $perFileActivityDB = "activity.db";
my $perFileActivityTable = "perfileactivity";

# get breadcrumbs for HTML view
sub get_breadcrumbs {
    my $dirPath = shift @_;

    my @breadcrumbs = ();
    my @dirs = File::Spec->splitdir($dirPath);

    my $pos = scalar(@dirs)-1;
    for (my $i=0; $i<$pos; $i++) {
        my $name = @dirs[$i];
        my $path = "../" x ($pos-$i);

        push (@breadcrumbs, {name => $name, path => $path});
    }

    return \@breadcrumbs;
}

sub setup_dbi {
    my ($sourceDB, $authorsDB, $blametokensDB, $queryKey) = @_;

    my ($dbName, $dbDir) = fileparse($sourceDB);
    $perFileActivityDB = File::Spec->catfile($dbDir, $perFileActivityDB);
    my $dsn = "dbi:SQLite:dbname=$perFileActivityDB";
    my $user = "";
    my $password = "";
    my $options = { RaiseError => 1, AutoCommit => 1 };
    $dbh = DBI->connect($dsn, $user, $password, $options) or die $DBI::errstr;
    $dbh->do("attach database '$authorsDB' as authorsdb;");
    $dbh->do("attach database '$sourceDB' as sourcedb;");
    $dbh->do("attach database '$blametokensDB' as blametokensdb;");
}

sub per_file_activity_dbi {
    print "Updating per file activity table ..";
    $dbh->do("DROP TABLE IF EXISTS $perFileActivityTable;");
    $dbh->do(
        "CREATE TABLE $perFileActivityTable (
        filename text,
        personid text,
        personname text,
        originalcid text,
        tokens int,
        autdate text);"
    );
    $dbh->do(
        "WITH t1 AS (SELECT filename, cid, COUNT(cid) AS tokenpercid FROM blametoken
        GROUP BY filename, cid) INSERT INTO $perFileActivityTable SELECT filename,
        personid, COALESCE(personname, 'Unknown'), originalcid, tokenpercid AS tokens,
        autdate FROM t1 LEFT JOIN commits ON (t1.cid=commits.cid) LEFT JOIN commitmap
        ON (t1.cid=commitmap.cid) LEFT JOIN emails ON (autname=emailname AND autemail
        =emailaddr) LEFT JOIN persons USING (personid) ORDER BY filename, tokens DESC;"
    );
    print ".Done!\n";
}

sub prepare_dbi {
    $fileSth = $dbh->prepare(
        "SELECT * FROM $perFileActivityTable WHERE filename=?;"
    );
    $fileTokenCountsSth = $dbh->prepare(
        "SELECT SUM(tokens) AS totaltokens FROM $perFileActivityTable WHERE filename=?;"
    );
    $fileAuthorsSth = $dbh->prepare(
        "SELECT personname, COUNT(DISTINCT originalcid) AS commits, SUM(tokens) AS tokens,
        COALESCE((CAST(SUM(tokens) AS float)/CAST((SELECT SUM(tokens) FROM $perFileActivityTable
        WHERE filename=?) AS float))), 0) AS tokenpercent FROM $perFileActivityTable WHERE
        filename=? GROUP BY personid ORDER BY tokens DESC;"
    );

    $dirSth = $dbh->prepare(
        "SELECT * FROM $perFileActivityTable where filename like '?%' and filename not
        like '?%/%';"
    );
    $dirTokenCountsSth = $dbh->prepare(
        "SELECT sum(tokens) FROM $perFileActivityTable where filename
        like '?%' and filename not like '?%/%';"
    );
    $dirAuthorsSth = $dbh->prepare(
        ""
    );
}

1;