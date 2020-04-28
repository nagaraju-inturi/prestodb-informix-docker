create database IF NOT EXISTS test;
use test;
create schema IF NOT EXISTS test;
create table tab (c1 int, c2 int, db char(30));
insert into tab values(1,1, 'mysql1');
insert into tab values(2,2, 'mysql2');
