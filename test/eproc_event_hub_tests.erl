%/--------------------------------------------------------------------
%| Copyright 2013-2014 Erisata, UAB (Ltd.)
%|
%| Licensed under the Apache License, Version 2.0 (the "License");
%| you may not use this file except in compliance with the License.
%| You may obtain a copy of the License at
%|
%|     http://www.apache.org/licenses/LICENSE-2.0
%|
%| Unless required by applicable law or agreed to in writing, software
%| distributed under the License is distributed on an "AS IS" BASIS,
%| WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%| See the License for the specific language governing permissions and
%| limitations under the License.
%\--------------------------------------------------------------------

%%%
%%% Tests for `eproc_event_hub`.
%%%
-module(eproc_event_hub_tests).
-compile([{parse_transform, lager_transform}]).
-include("eproc.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("hamcrest/include/hamcrest.hrl").

%%
%%
%%
notify_during_listen_test() ->
    {ok, Pid} = eproc_event_hub:start_link({local, eproc_event_hub_tests}),
    {ok, Session} = eproc_event_hub:listen(eproc_event_hub_tests, 2000),
    ok = eproc_event_hub:notify(eproc_event_hub_tests, my_event),
    receive after 100 -> ok end,
    {ok, my_event} = eproc_event_hub:recv(eproc_event_hub_tests, Session, [{my_event, [], ['$_']}]),
    unlink(Pid),
    exit(Pid, kill),
    ok.


%%
%%
%%
notify_during_recv_test() ->
    {ok, Pid} = eproc_event_hub:start_link({local, eproc_event_hub_tests}),
    {ok, Session} = eproc_event_hub:listen(eproc_event_hub_tests, 2000),
    spawn(fun () ->
        receive after 200 -> ok = eproc_event_hub:notify(eproc_event_hub_tests, my_event) end
    end),
    {ok, my_event} = eproc_event_hub:recv(eproc_event_hub_tests, Session, [{my_event, [], ['$_']}]),
    unlink(Pid),
    exit(Pid, kill),
    ok.

%%
%%
%%
timeout_during_listen_test() ->
    {ok, Pid} = eproc_event_hub:start_link({local, eproc_event_hub_tests}),
    {ok, Session} = eproc_event_hub:listen(eproc_event_hub_tests, 100),
    receive after 200 -> ok end,
    {error, timeout} = eproc_event_hub:recv(eproc_event_hub_tests, Session, [{my_event, [], ['$_']}]),
    unlink(Pid),
    exit(Pid, kill),
    ok.


%%
%%
%%
timeout_during_recv_test() ->
    {ok, Pid} = eproc_event_hub:start_link({local, eproc_event_hub_tests}),
    {ok, Session} = eproc_event_hub:listen(eproc_event_hub_tests, 100),
    {error, timeout} = eproc_event_hub:recv(eproc_event_hub_tests, Session, [{my_event, [], ['$_']}]),
    unlink(Pid),
    exit(Pid, kill),
    ok.


%%
%%
%%
no_session_test() ->
    {ok, Pid} = eproc_event_hub:start_link({local, eproc_event_hub_tests}),
    {ok, Session} = eproc_event_hub:listen(eproc_event_hub_tests, 100),
    ok = eproc_event_hub:notify(eproc_event_hub_tests, my_event),
    {ok, my_event}      = eproc_event_hub:recv(eproc_event_hub_tests, Session, [{my_event, [], ['$_']}]),
    {error, no_session} = eproc_event_hub:recv(eproc_event_hub_tests, Session, [{my_event, [], ['$_']}]),
    unlink(Pid),
    exit(Pid, kill),
    ok.


