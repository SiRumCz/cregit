package PrettyPrintDirView;
use strict;

use Date::Parse;
use Date::Format;
use DBI;
use File::Basename;
use File::Path;

# database handle and statement handle
my $dbh;
my $dirAuthorsSth;
my $dirGendersSth;
my $dirStatsCountSth;
my $subDirAuthorsSth;
my $subDirCountsSth;
my $subDirDateGroupSth;
my $subDirGenderGroupSth;
my $fileAuthorsSth;
my $fileCountsSth;
my $fileDateGroupSth;
my $fileGenderGroupSth;
my $minTimeSth;
my $maxTimeSth;

my $perFileActivityDB = "activity.db";
my $perFileActivityTable = "perfileactivity";
my $dategroupTable = "perfiledategroup";
my $directoryTmpTable = "tmp";
my $directoryGenderTmpTable = "gendertmp";
my $authorLimit = 60; # max number of authors to keep for each directory

# return authors list and stats (author count, commit count, token count)
sub get_directory_stats {
    my $dirPath = shift @_;

    # create directory stats table
    create_directory_table_dbi($dirPath);

    my $result;

    # fetch authors
    $result = $dirAuthorsSth->execute();
    my $authorsMeta = $dirAuthorsSth->fetchall_arrayref({});

    if (!defined $result) {
        Warning("Unable to retrieve authors for [$dirPath]");
    }

    $result = $dirStatsCountSth->execute();
    my $statsMeta = $dirStatsCountSth->fetchrow_hashref();

    if (! defined $result) {
        Warning("Unable to retrieve stats for [$dirPath]");
    }

    return ($authorsMeta, $statsMeta);
}

sub get_content_stats {
    my $contentPath = shift @_;
    my $type = shift @_;

    my $bindingVar1;
    my $bindingVar2;
    my $result;
    my $authorsMeta;

    # fetch authors
    if ('f' eq $type) {
        $bindingVar1 = "root/".$contentPath;
        $result = $fileAuthorsSth->execute($bindingVar1, $bindingVar1);
        $authorsMeta = $fileAuthorsSth->fetchall_arrayref({});
    } elsif ('d' eq $type) {
        $bindingVar1 = $contentPath."/";
        $bindingVar2 = $bindingVar1."{";
        $result = $subDirAuthorsSth->execute($bindingVar1, $bindingVar2, $bindingVar1, $bindingVar2);
        $authorsMeta = $subDirAuthorsSth->fetchall_arrayref({});
    }

    if (!defined $result) {
        Warning("Unable to retrieve authors for [$contentPath]");
    }

    my $statsMeta;
    if ('f' eq $type) {
        $result = $fileCountsSth->execute($bindingVar1);
        $statsMeta = $fileCountsSth->fetchrow_hashref();
    } elsif ('d' eq $type) {
        $result = $subDirCountsSth->execute($bindingVar1, $bindingVar2);
        $statsMeta = $subDirCountsSth->fetchrow_hashref();
    }

    if (!defined $result) {
        Warning("Unable to retrieve stats for [$contentPath]");
    }

    return ($authorsMeta, $statsMeta);
}

sub get_content_dategroup {
    my $contentPath = shift @_;
    my $type = shift @_;

    my @dateGroups = ();
    my $bindingVar1;
    my $bindingVar2;
    my $result;
    my $dategroupMeta;

    if ('f' eq $type) {
        $bindingVar1 = "root/".$contentPath;

        $result = $fileDateGroupSth->execute($bindingVar1);
        $dategroupMeta = $fileDateGroupSth->fetchall_arrayref;
    } elsif ('d' eq $type) {
        $bindingVar1 = $contentPath."/";
        $bindingVar2 = $bindingVar1."{";

        $result = $subDirDateGroupSth->execute($bindingVar1, $bindingVar2);
        $dategroupMeta = $subDirDateGroupSth->fetchall_arrayref;
    }

    if (! defined $result) {
        Warning("Unable to retrieve dategroup for [$contentPath]");
        return ();
    }

    my $lastGroup;
    my $index = 0;
    my $OthersTokenCount = 0;
    foreach (@{$dategroupMeta}) {
        my @currDategroup = @{$_};
        @currDategroup = ("1970-01-01 00:00:00", $authorLimit,"others", 0) unless (scalar @currDategroup == 4);

        my $dategroup = str2time(@currDategroup[0]);
        my $authorId = @currDategroup[1];
        my $authorGender = @currDategroup[2];
        my $tokenCount = @currDategroup[3];

        if (! defined $lastGroup) {
            push(@dateGroups, {
                timestr      => time2str("%B %Y", $dategroup),
                timestamp    => $dategroup,
                group        => undef,
                total_tokens => 0
            });
        } elsif ($dategroup != $lastGroup) {
            push(@dateGroups, {
                timestr      => time2str("%B %Y", $dategroup),
                timestamp    => $dategroup,
                group        => undef,
                total_tokens => 0
            });

            if ($OthersTokenCount > 0) {
                push(@{@dateGroups[$index]->{group}}, {
                    author_id     => $authorLimit,
                    author_gender => "others",
                    token_count   => $OthersTokenCount
                });
                $OthersTokenCount = 0;
            }

            $index++;
        }
        @dateGroups[$index]->{total_tokens} += $tokenCount;

        if ($authorId >= $authorLimit) {
            $OthersTokenCount += $tokenCount;
        } else {
            push(@{@dateGroups[$index]->{group}}, {
                author_id     => $authorId,
                author_gender => $authorGender,
                token_count   => $tokenCount
            });
        }

        $lastGroup = $dategroup;
    }

    if ($OthersTokenCount > 0) {
        push(@{@dateGroups[$index]->{group}}, {
            author_id     => $authorLimit,
            author_gender => "others",
            token_count   => $OthersTokenCount
        });
    }

    return [@dateGroups];
}

sub get_content_gendergroup {
    my $contentPath = shift @_;
    my $type = shift @_;

    my $bindingVar1;
    my $bindingVar2;
    my $result;
    my $genderMeta;

    if ('f' eq $type) {
        $bindingVar1 = "root/".$contentPath;

        $result = $fileGenderGroupSth->execute($bindingVar1, $bindingVar1);
        $genderMeta = $fileGenderGroupSth->fetchall_arrayref({});
    } elsif ('d' eq $type) {
        $bindingVar1 = $contentPath."/";
        $bindingVar2 = $bindingVar1."{";
        $result = $subDirGenderGroupSth->execute($bindingVar1, $bindingVar2, $bindingVar1, $bindingVar2);
        $genderMeta = $subDirGenderGroupSth->fetchall_arrayref({});
    }

    if (!defined $result) {
        Warning("Unable to retrieve gender group for [$contentPath]");
    }

    return $genderMeta;
}

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

# min max time for html date slider
sub get_minmax_time {
    my $dirPath = shift @_;
    my $bindingVar1 = $dirPath."/";
    my $bindingVar2 = $dirPath."/{";

    my $result;
    my @row;
    my $mintime;
    my $maxtime;

    $result = $minTimeSth->execute($bindingVar1, $bindingVar2);
    @row = $minTimeSth->fetchrow();

    if (! defined($result) or scalar(@row) != 1) {
        Warning("Unable to retrieve mintime for directory [$dirPath]");
        @row = ("1970-01-01 00:00:00");
    }

    $mintime = str2time(@row[0]);

    $result = $maxTimeSth->execute($bindingVar1, $bindingVar2);
    @row = $maxTimeSth->fetchrow();

    if (! defined($result) or scalar(@row) != 1) {
        Warning("Unable to retrieve maxtime for directory [$dirPath]");
        @row = ("2038-01-01 00:00:00");
    }

    $maxtime = str2time(@row[0]);

    return ($mintime, $maxtime);
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

# tables update
sub per_file_activity_dbi {
    $dbh->do("DROP TABLE IF EXISTS $perFileActivityTable;");
    $dbh->do("DROP TABLE IF EXISTS $dategroupTable;");
    $dbh->do("DROP TABLE IF EXISTS $directoryTmpTable;");

    $dbh->do(
        "CREATE TABLE IF NOT EXISTS $perFileActivityTable (
        filename text,
        personid text,
        personname text,
        persongender text,
        originalcid text,
        tokens int,
        autdate text);"
    );

    $dbh->do(
        "CREATE TABLE IF NOT EXISTS $dategroupTable (
        filename text,
        dategroup text,
        personid text,
        personname text,
        persongender text,
        tokens int);"
    );

    $dbh->do("DROP INDEX IF EXISTS f_act_index;");
    $dbh->do("DROP INDEX IF EXISTS f_dg_index;");
    $dbh->do("DELETE FROM $perFileActivityTable;");
    $dbh->do("DELETE FROM $dategroupTable;");
    # perfileactivity table : filename|personid|personname|originalcid|tokens in this commit|autdate
    $dbh->do(
        "WITH t1 AS (SELECT filename, cid, COUNT(cid) AS tokenspercid FROM blametoken
        GROUP BY filename, cid) INSERT INTO $perFileActivityTable SELECT 'root/'||filename,
        personid, COALESCE(personname, 'Unknown'), COALESCE(gender, 'unknown'), originalcid,
        tokenspercid AS tokens, autdate FROM t1 LEFT JOIN commits ON (t1.cid=commits.cid)
        LEFT JOIN commitmap ON (t1.cid=commitmap.cid) LEFT JOIN emails ON (autname=emailname
        AND autemail = emailaddr) LEFT JOIN persons USING (personid) ORDER BY filename, tokens DESC;"
    );
    # perfiledategroup table : filename|dategroup|personid|personname|tokens
    $dbh->do(
        "WITH t1 AS (SELECT *, SUBSTR(autdate, 1, 7)||'-01 00:00:00' AS dategroup FROM
        $perFileActivityTable) INSERT INTO $dategroupTable SELECT filename, t1.dategroup
        AS dategroup, personid, personname, persongender, SUM(tokens) AS tokens FROM t1
        GROUP BY filename, t1.dategroup, personid ORDER BY filename, dategroup;"
    );
    $dbh->do("CREATE INDEX f_act_index ON $perFileActivityTable (filename);");
    $dbh->do("CREATE INDEX f_act_gender_index ON $perFileActivityTable (persongender);");
    $dbh->do("CREATE INDEX f_dg_index ON $dategroupTable (filename);");
    $dbh->do("CREATE INDEX f_dg_gender_index ON $dategroupTable (persongender);");
}

sub create_directory_table_dbi {
    my $dirPath = shift @_;
    my $bindingVar1 = "\'".$dirPath."/\'";
    my $bindingVar2 = "\'".$dirPath."/{\'";

    $dbh->do(
        "CREATE TABLE IF NOT EXISTS $directoryTmpTable (
        personid text,
        personname text,
        persongender text,
        files text,
        tokens int,
        token_proportion text,
        commits int,
        commit_proportion text);"
    );

    # $dbh->do("DROP INDEX IF EXISTS f_dirtmp_index;");
    # $dbh->do("DROP INDEX IF EXISTS f_dirgender_index;");
    $dbh->do("DELETE FROM $directoryTmpTable;");
    $dbh->do(
        "WITH stats AS (SELECT SUM(tokens) AS tokens, COUNT(DISTINCT originalcid) AS commits FROM
        $perFileActivityTable WHERE filename between $bindingVar1 AND $bindingVar2) INSERT INTO
        $directoryTmpTable SELECT personid, personname, persongender, COUNT(DISTINCT filename) AS
        files, SUM(tokens) AS tokens, COALESCE(CAST(SUM(tokens) AS float) / NULLIF(CAST((SELECT
        tokens FROM stats) AS float) , 0), 0) AS token_proportion, COUNT(DISTINCT originalcid) AS
        commits, COALESCE(CAST(COUNT(DISTINCT originalcid) AS float) / NULLIF(CAST((SELECT commits
        FROM stats) AS float), 0), 0) AS commit_proportion FROM $perFileActivityTable WHERE filename
        between $bindingVar1 AND $bindingVar2 GROUP BY personid ORDER BY tokens DESC;"
    ); # personid|personname|persongender|files|tokens|token_proportion|commits|commit_proportion
    $dbh->do("CREATE INDEX IF NOT EXISTS f_dirtmp_index ON $directoryTmpTable (personid);");
    $dbh->do("CREATE INDEX IF NOT EXISTS f_dirgender_index ON $directoryTmpTable (persongender);");

    return prepare_dbi();
}

sub prepare_dbi {
    $dirAuthorsSth = $dbh->prepare(
        "WITH t1 AS (SELECT rowid-1 AS id, rowid-1 AS color_id, personname AS name, files,
        tokens, token_proportion, printf(\"%.2f%%\", token_proportion*100) AS token_percent,
        commits, commit_proportion, printf(\"%.2f%%\", commit_proportion*100) AS commit_percent FROM
        $directoryTmpTable LIMIT $authorLimit), t2 AS (SELECT $authorLimit AS id, 'Black' AS color_id,
        'Others' AS name, SUM(files) AS files, SUM(tokens) AS tokens, SUM(token_proportion) AS
        token_proportion, printf(\"%.2f%%\", SUM(token_proportion)*100) AS token_percent , SUM(commits)
        AS commits, SUM(commit_proportion) AS commit_proportion, printf(\"%.2f%%\", SUM(commit_proportion
        )*100) AS commit_percent FROM $directoryTmpTable WHERE rowid > $authorLimit) SELECT *, 1 AS od
        FROM t1 UNION ALL SELECT *, 2 AS od FROM t2 WHERE t2.tokens IS NOT NULL ORDER BY od;"
    ); # id|color_id|name|files|tokens|token_proportion|commits|commit_proportion

    $dirGendersSth = $dbh->prepare(
        "SELECT persongender, COUNT(DISTINCT personid) AS authors, SUM(tokens) AS tokens, SUM(token_proportion)
        AS token_proportion, SUM(commits) AS commits, SUM(commit_proportion) AS commit_proportion FROM
        $directoryTmpTable GROUP BY persongender ORDER BY tokens DESC;"
    );

    $dirStatsCountSth = $dbh->prepare(
        "SELECT COUNT(DISTINCT personid) AS author_counts, COALESCE(SUM(commits), 0) AS commit_counts,
        COALESCE(SUM(tokens), 0) AS tokens FROM $directoryTmpTable;"
    );

    $subDirAuthorsSth = $dbh->prepare(
        "WITH stats AS (SELECT SUM(tokens) AS tokens, COUNT(originalcid) AS commits FROM $perFileActivityTable
        WHERE filename BETWEEN ? AND ?), t1 AS (SELECT personid, personname, persongender, SUM(tokens) AS
        tokens, COALESCE(CAST(SUM(tokens) AS float) / NULLIF(CAST((SELECT tokens FROM stats) AS float) , 0),
        0) AS token_proportion, COUNT(DISTINCT originalcid) AS commits, COALESCE(CAST(COUNT(DISTINCT
        originalcid) AS float) / NULLIF(CAST((SELECT commits FROM stats) AS float), 0), 0) AS commit_proportion
        FROM $perFileActivityTable WHERE filename BETWEEN ? AND ? GROUP BY personid ORDER BY tokens DESC), t2 AS
        (SELECT $directoryTmpTable.rowid-1 AS id, $directoryTmpTable.rowid-1 AS color_id, t1.personname AS name,
        t1.persongender AS gender, t1.tokens, t1.token_proportion, printf(\"%.2f%%\", t1.token_proportion*100)
        AS token_percent FROM t1 INNER JOIN $directoryTmpTable on (t1.personid=$directoryTmpTable.personid) WHERE
        id < $authorLimit ORDER BY t1.tokens DESC), t3 AS (SELECT $authorLimit AS id, 'Black' AS color_id,
        'Others' AS name, 'others' AS gender, SUM(t1.tokens) AS tokens, SUM(t1.token_proportion) AS
        token_proportion, printf(\"%.2f%%\", SUM(t1.token_proportion)*100) AS token_percent FROM t1 INNER JOIN
        $directoryTmpTable on(t1.personid=$directoryTmpTable.personid) WHERE $directoryTmpTable.rowid > $authorLimit)
        SELECT *, 1 AS od FROM t2 UNION ALL SELECT *, 2 AS od FROM t3 WHERE t3.tokens IS NOT NULL ORDER BY od;"
    ); # id|color_id|personname|gender|tokens|token_proportion

    $subDirCountsSth = $dbh->prepare(
        "SELECT COUNT(DISTINCT personid) AS author_counts, COALESCE(SUM(tokens), 0) AS tokens FROM $perFileActivityTable
        WHERE filename BETWEEN ? AND ?;"
    );

    $subDirDateGroupSth = $dbh->prepare(
        "SELECT t1.dategroup, t2.rowid-1 AS id, t2.persongender, SUM(t1.tokens) AS tokens FROM $dategroupTable AS t1 INNER JOIN
        $directoryTmpTable AS t2 ON(t1.personid=t2.personid) WHERE filename BETWEEN ? AND ? GROUP BY t1.dategroup,
        t1.personid ORDER BY t1.dategroup;"
    );

    $subDirGenderGroupSth = $dbh->prepare(
        "WITH stats AS (SELECT COALESCE(SUM(tokens), 0) AS tokens FROM $perFileActivityTable WHERE filename
        BETWEEN ? AND ?), t1 AS (SELECT personid, persongender, COALESCE(SUM(tokens), 0) AS tokens, COALESCE(CAST(
        SUM(tokens) AS float) / NULLIF(CAST((SELECT tokens FROM stats) AS float) ,
        0), 0) AS token_proportion FROM $perFileActivityTable WHERE filename BETWEEN ? AND ? GROUP BY
        personid ORDER BY tokens DESC), male AS (SELECT 'male' AS gendergroup, COALESCE(SUM(t1.tokens), 0) AS tokens
        FROM t1 INNER JOIN $directoryTmpTable on (t1.personid = $directoryTmpTable.personid) WHERE
        t1.persongender = 'male' AND $directoryTmpTable.rowid <= $authorLimit), female AS (SELECT 'female' AS
        gendergroup, COALESCE(SUM(t1.tokens), 0) AS tokens FROM t1 INNER JOIN $directoryTmpTable on (t1.personid
        = $directoryTmpTable.personid) WHERE t1.persongender = 'female' AND $directoryTmpTable.rowid <=
        $authorLimit), others AS (SELECT 'others' AS gendergroup, COALESCE(SUM(t1.tokens), 0) AS tokens FROM t1 INNER
        JOIN $directoryTmpTable on (t1.personid=$directoryTmpTable.personid) WHERE $directoryTmpTable.rowid
        > $authorLimit) SELECT *, printf(\"%.2f%%\", COALESCE(CAST(tokens AS float) / NULLIF(CAST((SELECT tokens FROM
        stats) AS float), 0), 0)*100) AS token_percent, 1 AS od FROM male UNION ALL SELECT *,
        printf(\"%.2f%%\", COALESCE(CAST(tokens AS float) / NULLIF(CAST((SELECT tokens FROM stats
        ) AS float), 0), 0)*100) AS token_percent, 2 AS od FROM female UNION ALL SELECT *, printf(\"%.2f%%\",
        COALESCE(CAST(tokens AS float) / NULLIF(CAST((SELECT tokens FROM stats) AS float), 0)
        , 0)*100) AS token_percent, 3 AS od FROM others WHERE others.tokens IS NOT NULL ORDER BY od;"
    );

    $fileAuthorsSth = $dbh->prepare(
        "WITH stats AS (SELECT SUM(tokens) AS tokens, COUNT(originalcid) AS commits FROM $perFileActivityTable
        WHERE filename = ?), t1 AS (SELECT personid, personname, persongender, SUM(tokens) AS
        tokens, COALESCE(CAST(SUM(tokens) AS float) / NULLIF(CAST((SELECT tokens FROM stats) AS float) , 0),
        0) AS token_proportion, COUNT(DISTINCT originalcid) AS commits, COALESCE(CAST(COUNT(DISTINCT
        originalcid) AS float) / NULLIF(CAST((SELECT commits FROM stats) AS float), 0), 0) AS commit_proportion
        FROM $perFileActivityTable WHERE filename = ? GROUP BY personid ORDER BY tokens DESC), t2 AS
        (SELECT $directoryTmpTable.rowid-1 AS id, $directoryTmpTable.rowid-1 AS color_id, t1.personname AS name,
        t1.persongender AS gender, t1.tokens, t1.token_proportion, printf(\"%.2f%%\", t1.token_proportion*100)
        AS token_percent FROM t1 INNER JOIN $directoryTmpTable on (t1.personid=$directoryTmpTable.personid) WHERE
        id < $authorLimit ORDER BY t1.tokens DESC), t3 AS (SELECT $authorLimit AS id, 'Black' AS color_id,
        'Others' AS name, 'others' AS gender, SUM(t1.tokens) AS tokens, SUM(t1.token_proportion) AS
        token_proportion, printf(\"%.2f%%\", SUM(t1.token_proportion)*100) AS token_percent FROM t1 INNER JOIN
        $directoryTmpTable on(t1.personid=$directoryTmpTable.personid) WHERE $directoryTmpTable.rowid > $authorLimit)
        SELECT *, 1 AS od FROM t2 UNION ALL SELECT *, 2 AS od FROM t3 WHERE t3.tokens IS NOT NULL ORDER BY od;"
    ); # id|color_id|personname|gender|tokens|token_proportion

    $fileCountsSth = $dbh->prepare(
        "SELECT COUNT(DISTINCT personid) AS author_counts, COALESCE(SUM(tokens), 0) AS tokens FROM $perFileActivityTable
        WHERE filename = ?;"
    );

    $fileDateGroupSth = $dbh->prepare(
        "SELECT t1.dategroup, t2.rowid-1 AS id, t2.persongender, SUM(t1.tokens) AS tokens FROM $dategroupTable AS t1 INNER JOIN
        $directoryTmpTable AS t2 ON(t1.personid=t2.personid) WHERE filename = ? GROUP BY t1.dategroup, t1.personid
        ORDER BY t1.dategroup;"
    );

    $fileGenderGroupSth = $dbh->prepare(
        "WITH stats AS (SELECT COALESCE(SUM(tokens), 0) AS tokens FROM $perFileActivityTable WHERE filename
        = ?), t1 AS (SELECT personid, persongender, COALESCE(SUM(tokens), 0) AS tokens, COALESCE(CAST(
        SUM(tokens) AS float) / NULLIF(CAST((SELECT tokens FROM stats) AS float) ,
        0), 0) AS token_proportion FROM $perFileActivityTable WHERE filename = ? GROUP BY
        personid ORDER BY tokens DESC), male AS (SELECT 'male' AS gendergroup, COALESCE(SUM(t1.tokens), 0) AS tokens
        FROM t1 INNER JOIN $directoryTmpTable on (t1.personid = $directoryTmpTable.personid) WHERE
        t1.persongender = 'male' AND $directoryTmpTable.rowid <= $authorLimit), female AS (SELECT 'female' AS
        gendergroup, COALESCE(SUM(t1.tokens), 0) AS tokens FROM t1 INNER JOIN $directoryTmpTable on (t1.personid
        = $directoryTmpTable.personid) WHERE t1.persongender = 'female' AND $directoryTmpTable.rowid <=
        $authorLimit), others AS (SELECT 'others' AS gendergroup, COALESCE(SUM(t1.tokens), 0) AS tokens FROM t1 INNER
        JOIN $directoryTmpTable on (t1.personid=$directoryTmpTable.personid) WHERE $directoryTmpTable.rowid
        > $authorLimit) SELECT *, printf(\"%.2f%%\", COALESCE(CAST(tokens AS float) / NULLIF(CAST((SELECT tokens FROM
        stats) AS float), 0), 0)*100) AS token_percent, 1 AS od FROM male UNION ALL SELECT *,
        printf(\"%.2f%%\", COALESCE(CAST(tokens AS float) / NULLIF(CAST((SELECT tokens FROM stats
        ) AS float), 0), 0)*100) AS token_percent, 2 AS od FROM female UNION ALL SELECT *, printf(\"%.2f%%\",
        COALESCE(CAST(tokens AS float) / NULLIF(CAST((SELECT tokens FROM stats) AS float), 0)
        , 0)*100) AS token_percent, 3 AS od FROM others WHERE others.tokens IS NOT NULL ORDER BY od;"
    );

    $minTimeSth = $dbh->prepare(
        "SELECT MIN(autdate) FROM $perFileActivityTable WHERE filename BETWEEN ? AND ?;"
    );
    $maxTimeSth = $dbh->prepare(
        "SELECT MAX(autdate) FROM $perFileActivityTable WHERE filename BETWEEN ? AND ?;"
    );

    return 0;
}

sub Error {
    my $message = shift @_;
    print STDERR "Error: ", $message, "\n";
    return 1;
}

sub Warning {
    my $message = shift @_;
    print STDERR "Warning: ", $message, "\n";
    return 1;
}

1;
