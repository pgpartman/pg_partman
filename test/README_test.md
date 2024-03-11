pg_partman Test Suite
=====================

The pgTAP testing suite is used to provide an extensive and easily maintainable set of unit tests. Please see the pgTAP home page for more details on its installation and use.

http://pgtap.org/

A minimum version of pgtap 1.2.0 is required for pg_partman's test suite.

***WARNING: You MUST increase max_locks_per_transaction above the default value of 64. A value of 128 has worked well so far with existing tests. This is due to the subpartitioning tests that create/destroy several hundred tables in a single transaction. If you don't do this, you risk a cluster crash when running subpartitioning tests.***

Tests assume that the required extensions have been installed in the following schemas:

    pg_partman: partman
    pgTAP: public

If you've installed any of the above extensions in a different schema and would like to run the test suite, simply change the configuration option found at the top of each testing file to match your setup. If you've also installed pg_jobmon, be aware that the logging of the tests cannot be rolled back and any failures will be picked up by the monitoring in the jobmon extension.

```sql
    SELECT set_config('search_path','partman, public',false);
```

Once that's done, it's best to use the **pg_prove** script that pgTAP comes with to run all the tests. If you don't have pg_prove available from your installation source, it is typically available via a perl library package (Ex. `libtap-parser-sourcehandler-pgtap-perl` on Ubuntu).

I like using the  -o, -v -f options to get more useful feedback.

```sql
    pg_prove -ovf /path/to/partman/test/*.sql
```

For tests on the top level of the `test` folder, you should be able to run all of them at once with the wildcard as in the above example. Test in sub-folders may require special setup or conditions and should only be run individually after careful review of each test to know what is expected. See notes below.

For most tests, they must be run by a superuser since roles & schemas are created & dropped as part of the test. The tests are not required to run pg_partman, so if you don't feel safe doing this you don't need to run the tests. But if you are running into problems and report any issues without a clear explanation of what is wrong, I will ask that you run the test suite so you can try and narrow down where the problem may be. All tests in the top level of the test folder are run inside a transaction that is rolled back, so they should not change anything (except jobmon logging as mentioned). Note that some tests in sub-folders are not run in a single rolled-back transaction, but do have a final step to perform cleanup.

The 30second test frequently errors out if run in certain 30 second blocks. Waiting for the next 30 second block and running it again should allow it to pass.

Tests for the Background Worker can be found in the test/test_bgw folder. Please read the header comments at the top of each test for the postgresql.conf settings required for that test.

Tests for procedures are in their own folders. These must be run in stages with manual commands between them since pgTap cannot handle distinct commits within a single test run.

Tests for the reindexing script are in development and will return once the reindexing feature has been updated. They can be found in the test/test_reindex folder. These tests cannot just be run all at once and are not run within rolled back transactions. They must be run in order, one at a time, and there are explicit instructions at the end of each test for what to do next.
