--create database quicksightpoc;

create table if not exists quicksightpoc.public.systems (
	name varchar(50) constraint namekey primary key
);

insert into quicksightpoc.public.systems values('quicksight-poc-1');

select * from quicksightpoc.public.systems;