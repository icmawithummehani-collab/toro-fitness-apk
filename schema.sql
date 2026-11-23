create extension if not exists pgcrypto;
create type public.app_role as enum ('owner_admin','member');
create type public.subscription_status as enum ('pending','active','expired','frozen','cancelled');
create type public.payment_method as enum ('cash','bank_transfer','card','other');
create sequence public.receipt_seq;

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 role public.app_role not null default 'member',
 full_name text not null, phone text, email text, created_at timestamptz not null default now());
create table public.members (
 id uuid primary key default gen_random_uuid(),
 user_id uuid unique references public.profiles(id) on delete set null,
 member_code text unique not null, full_name text not null, phone text not null, email text,
 joining_date date not null default current_date, created_at timestamptz not null default now());
create table public.membership_plans (
 id uuid primary key default gen_random_uuid(), name text not null unique,
 duration_days int not null check(duration_days>0),
 price_pkr numeric(12,2) not null check(price_pkr>=0),
 is_active boolean not null default true);
create table public.subscriptions (
 id uuid primary key default gen_random_uuid(),
 member_id uuid not null references public.members(id),
 plan_id uuid not null references public.membership_plans(id),
 start_date date not null, end_date date not null,
 status public.subscription_status not null default 'pending',
 fee_pkr numeric(12,2) not null check(fee_pkr>=0),
 frozen_at timestamptz, activated_at timestamptz,
 created_by uuid default auth.uid() references public.profiles(id),
 created_at timestamptz not null default now(), check(end_date>=start_date));
create table public.payments (
 id uuid primary key default gen_random_uuid(),
 member_id uuid not null references public.members(id),
 subscription_id uuid references public.subscriptions(id),
 amount_pkr numeric(12,2) not null check(amount_pkr>0),
 paid_at timestamptz not null default now(), method public.payment_method not null,
 receipt_number text unique not null default ('TF-'||lpad(nextval('public.receipt_seq')::text,6,'0')),
 recorded_by uuid not null default auth.uid() references public.profiles(id), notes text);
create table public.checkin_codes (
 id uuid primary key default gen_random_uuid(),
 member_id uuid not null references public.members(id) on delete cascade,
 code text not null, expires_at timestamptz not null, used_at timestamptz,
 created_at timestamptz not null default now());
create table public.attendance (
 id uuid primary key default gen_random_uuid(),
 member_id uuid not null references public.members(id),
 member_name text not null, code_id uuid references public.checkin_codes(id) on delete set null,
 marked_by uuid default auth.uid(), checked_in_at timestamptz not null default now());
create table public.audit_logs (
 id bigint generated always as identity primary key, actor_id uuid,
 action text not null, entity_type text not null, entity_id text,
 details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());

create index subs_member_idx on public.subscriptions(member_id,status,end_date);
create index pay_member_idx on public.payments(member_id,paid_at desc);
create index att_time_idx on public.attendance(checked_in_at desc);
create index codes_idx on public.checkin_codes(code) where used_at is null;

create function public.is_admin() returns boolean language sql stable security definer
set search_path=public as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='owner_admin') $$;
create function public.current_member_id() returns uuid language sql stable security definer
set search_path=public as $$ select id from public.members where user_id=auth.uid() limit 1 $$;

alter table public.profiles enable row level security;
alter table public.members enable row level security;
alter table public.membership_plans enable row level security;
alter table public.subscriptions enable row level security;
alter table public.payments enable row level security;
alter table public.checkin_codes enable row level security;
alter table public.attendance enable row level security;
alter table public.audit_logs enable row level security;

create policy profile_select on public.profiles for select using(id=auth.uid() or public.is_admin());
create policy members_admin_all on public.members for all using(public.is_admin()) with check(public.is_admin());
create policy members_own on public.members for select using(user_id=auth.uid());
create policy plans_select on public.membership_plans for select using(is_active or public.is_admin());
create policy plans_admin_all on public.membership_plans for all using(public.is_admin()) with check(public.is_admin());
-- Only the business can create/assign plans and write payments. Members can only READ their own rows.
create policy subs_admin_all on public.subscriptions for all using(public.is_admin()) with check(public.is_admin());
create policy subs_own on public.subscriptions for select using(member_id=public.current_member_id());
create policy pay_admin_all on public.payments for all using(public.is_admin()) with check(public.is_admin());
create policy pay_own on public.payments for select using(member_id=public.current_member_id());
create policy att_admin_select on public.attendance for select using(public.is_admin());
create policy audit_admin_select on public.audit_logs for select using(public.is_admin());
-- checkin_codes: no policies = no direct client access; use the functions below.

-- Freeze / resume / cancel: business AND member (own plan only).
-- Resuming extends end_date by the days the plan was frozen.
create function public.set_subscription_status(p_sub uuid, p_status public.subscription_status)
returns void language plpgsql security definer set search_path=public as $$
declare s public.subscriptions%rowtype;
begin
 select * into s from subscriptions where id=p_sub for update;
 if not found then raise exception 'Subscription not found'; end if;
 if not public.is_admin() and s.member_id is distinct from public.current_member_id() then raise exception 'Not allowed'; end if;
 if p_status not in ('active','frozen','cancelled') then raise exception 'Invalid status'; end if;
 if s.status='cancelled' then raise exception 'Already cancelled'; end if;
 if p_status='frozen' and s.status<>'active' then raise exception 'Only active plans can be frozen'; end if;
 if p_status='active' and s.status<>'frozen' then raise exception 'Only frozen plans can be resumed'; end if;
 update subscriptions set status=p_status,
  frozen_at=case when p_status='frozen' then now() else null end,
  end_date=case when p_status='active' then s.end_date+greatest(0,current_date-s.frozen_at::date) else s.end_date end
 where id=p_sub;
 insert into audit_logs(actor_id,action,entity_type,entity_id) values(auth.uid(),'subscription_'||p_status,'subscription',p_sub::text);
end $$;

-- Member: a NEW code on every check-in (valid 10 minutes, single use).
create function public.generate_checkin_code() returns text language plpgsql security definer
set search_path=public,extensions as $$
declare m uuid:=public.current_member_id(); c text;
begin
 if m is null then raise exception 'Member profile not found'; end if;
 if not exists(select 1 from subscriptions where member_id=m and status='active' and current_date between start_date and end_date)
  then raise exception 'No active membership'; end if;
 delete from checkin_codes where member_id=m;
 loop
  c:=lpad((('x'||encode(gen_random_bytes(4),'hex'))::bit(32)::bigint % 1000000)::text,6,'0');
  exit when not exists(select 1 from checkin_codes where code=c and used_at is null and expires_at>now());
 end loop;
 insert into checkin_codes(member_id,code,expires_at) values(m,c,now()+interval '10 minutes');
 return c;
end $$;

-- Admin: member tells the code, admin marks attendance.
create function public.mark_attendance(p_code text) returns jsonb language plpgsql security definer
set search_path=public as $$
declare k public.checkin_codes%rowtype; mn text;
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 select * into k from checkin_codes where code=trim(p_code) and used_at is null and expires_at>now()
  order by created_at desc limit 1 for update;
 if not found then return jsonb_build_object('ok',false,'message','Invalid or expired code'); end if;
 select full_name into mn from members where id=k.member_id;
 if not exists(select 1 from subscriptions where member_id=k.member_id and status='active' and current_date between start_date and end_date)
  then return jsonb_build_object('ok',false,'message',mn||': membership is not active'); end if;
 update checkin_codes set used_at=now() where id=k.id;
 insert into attendance(member_id,member_name,code_id) values(k.member_id,mn,k.id);
 return jsonb_build_object('ok',true,'message',mn||' checked in');
end $$;

-- Admin dashboard numbers. p_period: today | week | month | year | all
create function public.admin_dashboard(p_period text default 'month') returns jsonb language plpgsql stable
security definer set search_path=public as $$
declare ln timestamp:=now() at time zone 'Asia/Karachi'; f timestamptz; t0 timestamptz;
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 t0:=date_trunc('day',ln) at time zone 'Asia/Karachi';
 f:=case p_period when 'today' then t0 when 'week' then now()-interval '7 days'
  when 'month' then date_trunc('month',ln) at time zone 'Asia/Karachi'
  when 'year' then date_trunc('year',ln) at time zone 'Asia/Karachi' else '-infinity'::timestamptz end;
 return jsonb_build_object(
  'active_members',(select count(distinct member_id) from subscriptions where status='active' and current_date between start_date and end_date),
  'checkins_today',(select count(*) from attendance where checked_in_at>=t0),
  'revenue',(select coalesce(sum(amount_pkr),0) from payments where paid_at>=f),
  'outstanding',(select coalesce(sum(greatest(s.fee_pkr-coalesce((select sum(p.amount_pkr) from payments p where p.subscription_id=s.id),0),0)),0)
     from subscriptions s where s.status in ('pending','active','frozen')),
  'expiring',(select coalesce(jsonb_agg(jsonb_build_object('name',m.full_name,'end_date',s.end_date) order by s.end_date),'[]'::jsonb)
     from subscriptions s join members m on m.id=s.member_id
     where s.status='active' and s.end_date between current_date and current_date+7));
end $$;

revoke all on function public.set_subscription_status(uuid,public.subscription_status), public.generate_checkin_code(),
 public.mark_attendance(text), public.admin_dashboard(text) from public, anon;
grant execute on function public.set_subscription_status(uuid,public.subscription_status), public.generate_checkin_code(),
 public.mark_attendance(text), public.admin_dashboard(text) to authenticated;

alter publication supabase_realtime add table public.attendance;

-- Assumed starter plans (editable in the app, Plans tab)
insert into public.membership_plans(name,duration_days,price_pkr) values
('Monthly',30,6000),('Quarterly',90,16000),('Yearly',365,55000),('Day Pass',1,1000)
on conflict(name) do nothing;
