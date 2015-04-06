

# Module eproc_event_hub #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)



<a name="types"></a>

## Data Types ##




### <a name="type-session_ref">session_ref()</a> ###


__abstract datatype__: `session_ref()`

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#code_change-3">code_change/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_call-3">handle_call/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_cast-2">handle_cast/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#listen-2">listen/2</a></td><td></td></tr><tr><td valign="top"><a href="#notify-2">notify/2</a></td><td></td></tr><tr><td valign="top"><a href="#recv-3">recv/3</a></td><td></td></tr><tr><td valign="top"><a href="#start-1">start/1</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td></td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="code_change-3"></a>

### code_change/3 ###

`code_change(OldVsn, State, Extra) -> any()`


<a name="handle_call-3"></a>

### handle_call/3 ###

`handle_call(X1, From, State) -> any()`


<a name="handle_cast-2"></a>

### handle_cast/2 ###

`handle_cast(X1, State) -> any()`


<a name="handle_info-2"></a>

### handle_info/2 ###

`handle_info(X1, State) -> any()`


<a name="init-1"></a>

### init/1 ###

`init(X1) -> any()`


<a name="listen-2"></a>

### listen/2 ###


<pre><code>
listen(Name::<a href="#type-otp_ref">otp_ref()</a>, Duration::integer()) -&gt; {ok, SessionRef::<a href="#type-session_ref">session_ref()</a>}
</code></pre>

<br></br>



<a name="notify-2"></a>

### notify/2 ###


<pre><code>
notify(Name::<a href="#type-otp_ref">otp_ref()</a>, Event::term()) -&gt; ok
</code></pre>

<br></br>



<a name="recv-3"></a>

### recv/3 ###


<pre><code>
recv(Name::<a href="#type-otp_ref">otp_ref()</a>, SessionRef::<a href="#type-session_ref">session_ref()</a>, MatchSpec::<a href="ets.md#type-match_spec">ets:match_spec()</a>) -&gt; {ok, Event::term()} | {error, Reason::term()}
</code></pre>

<br></br>



<a name="start-1"></a>

### start/1 ###


<pre><code>
start(Name::<a href="#type-otp_name">otp_name()</a>) -&gt; {ok, pid()} | ignore | {error, term()}
</code></pre>

<br></br>



<a name="start_link-1"></a>

### start_link/1 ###


<pre><code>
start_link(Name::<a href="#type-otp_name">otp_name()</a>) -&gt; {ok, pid()} | ignore | {error, term()}
</code></pre>

<br></br>



<a name="terminate-2"></a>

### terminate/2 ###

`terminate(Reason, State) -> any()`


