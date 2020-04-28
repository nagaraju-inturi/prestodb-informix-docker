# prestdb-informix-docker
Docker Image for PrestoDB + Informix + MySQL + PostgreSQL

Note: To build this image, you need ibm.ids.14.10.FC1.LNX.tar and clientsdk.4.50.tar tar files from IBM. Copy these tar files to server_ctx dir.

# presto --server 127.0.0.1:8090 
presto> select * from informix.informix.tab i,mysql.test.tab m, postgresql.public.tab p where i.c1=m.c1 and i.c1=p.c1;
 c1 | c2 |               db               | c1 | c2 |               db               | c1 | c2 |               db               
----+----+--------------------------------+----+----+--------------------------------+----+----+--------------------------------
  1 |  1 | informix1                      |  1 |  1 | mysql1                         |  1 |  1 | postgresql1                    
  2 |  2 | informix2                      |  2 |  2 | mysql2                         |  2 |  2 | postgresql2                    
(2 rows)

Query 20200428_054822_00001_t8fcj, FINISHED, 1 node
Splits: 99 total, 99 done (100.00%)
0:03 [6 rows, 0B] [1 rows/s, 0B/s]

presto> 






