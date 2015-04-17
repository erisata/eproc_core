

# Module eproc_fsm_mfa_sup #
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`supervisor`](supervisor.md).
<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#start_fsm-3">start_fsm/3</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="init-1"></a>

### init/1 ###

`init(X1) -> any()`


<a name="start_fsm-3"></a>

### start_fsm/3 ###


<pre><code>
start_fsm(Supervisor::<a href="#type-otp_ref">otp_ref()</a>, FsmRef::<a href="#type-fsm_ref">fsm_ref()</a>, StartMFA::<a href="#type-mfargs">mfargs()</a>) -&gt; {ok, pid()}
</code></pre>

<br></br>



<a name="start_link-1"></a>

### start_link/1 ###


<pre><code>
start_link(Name::<a href="#type-otp_name">otp_name()</a>) -&gt; pid() | {error, term()} | term()
</code></pre>

<br></br>



