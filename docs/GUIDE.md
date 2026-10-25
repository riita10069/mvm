mvm

AWS Lambda MicroVMs の上に、使い捨ての開発用 VM を立てる道具です。手元に入れるのは zsh の関数、ssh の ProxyCommand 用シェルスクリプト、websocat だけで、AWS への操作は aws CLI をそのまま呼びます。呼んだ aws コマンドは毎回 stderr に表示されます。表示しないのは TAB 補完の裏で候補を引く呼び出しだけです。VM は microvm ID で扱い、手元のディレクトリとは結び付けず、ファイルの同期もしません。コードは VM の中で git clone し、VM から push します。

構成

terraform/ はイメージを作るのに必要なものをすべて作ります。S3 のビルドコンテキスト用バケット、ビルドロール、VM の実行ロール、CloudWatch Logs のロググループ、MicroVM イメージです。イメージは CloudFormation の AWS::Lambda::MicrovmImage として作ります。Terraform AWS provider 6.70 の aws_lambdamicrovms_image には hooks と logging の設定がなく、VM に公開鍵を配る /run フックを有効にできないためです。実行ロールの ARN はイメージの mvm:execution-role タグに入れるので、手元に設定ファイルは要りません。

image/ はイメージの中身です。Amazon Linux 2023 の arm64 に、git、gh、Claude Code、Codex、Gemini CLI、AWS CLI、AWS CDK、Terraform、kubectl、helm、ripgrep、fd、fzf、bat、jq、yq、delta、lazygit、neovim、tmux、zsh、uv、psql と mysql と redis のクライアントを入れています。GitHub のリリースから取るバイナリは版と sha256 を固定しています。言語のツールチェーンは入れていません。VM のディスクは 8 GB 固定で、イメージと作業領域がこれを分け合うためです。入っているのは、コーディングエージェントを動かす Node 22 と npm、mvm-agent が使うシステムの Python 3.9、npm のネイティブモジュールをビルドする gcc と make だけです。Go、Rust、Python 3.12、Java、Ruby、pnpm と yarn、cmake などのビルド用ライブラリ、clang、gdb、valgrind は、VM の中で mvm-install go rust のように実行して入れます。イメージは約 2.4 GB で、VM に入った直後のディスクの空きは約 4.2 GB です。 VM の入口は image/files/mvm-agent.py で、ポート 9000 でライフサイクルフックを受け、ポート 2222 の WebSocket を websocat で sshd に中継します。ホスト鍵、authorized_keys、環境変数は /run で VM ごとに作ります。イメージのスナップショットは /ready の時点で撮られ、全 VM がそこから起動するためです。

Claude Code は Bedrock の Anthropic モデル、Codex は Bedrock の openai.gpt-5.5 を、どちらも VM の実行ロールで使います。API キーは要りません。gpt-5.5 は us-east-1 の bedrock-mantle でしか提供されていないので、Codex だけは us-east-1 を呼びます。

shell/mvm.zsh が mvm コマンドと補完、bin/mvm-proxy が ssh の ProxyCommand、ssh/config が Host microvm-* の設定です。

準備

```bash
brew install awscli jq websocat
cd terraform && terraform init && terraform apply     # イメージのビルドに 10 分ほどかかる
```

mvm の操作には ssh の設定は要りません。mvm.zsh が ssh/config と同じ設定を ssh のオプションで直接渡すためです。~/.ssh/config の先頭に次の 1 行を足すと、素の ssh、scp、rsync、VS Code Remote-SSH からも microvm-<id> に入れます。ssh/config の ProxyCommand はこのリポジトリが ~/code/github.com/riita10069/mvm にある前提の絶対パスなので、別の場所に置いたときは書き換えてください。

```
Include ~/code/github.com/riita10069/mvm/ssh/config
```

~/.zshrc（または ~/.zshrc から読む ~/.zshrc.local）で読み込みます。compinit の前でもあとでもかまいません。

```zsh
source ~/code/github.com/riita10069/mvm/shell/mvm.zsh
```

使い方

```
mvm up [-i イメージ名] [--no-clone]   起動し、GitHub のトークンを渡し、カレントのリポジトリを clone して入る
mvm ls [-a]                           ID、状態、イメージ、起動時刻、残り時間、clone したリポジトリ（-a は終了済みも）
mvm <ID>                              入る。ssh <ID> と同じで、suspend 中なら接続で再開する
mvm <ID> <操作>                       その VM に stop、resume、rm、clone、gh-login、ssh のどれかをする
mvm <ID> -- <コマンド>                VM の中でコマンドを実行する
mvm stop|resume|rm|clone|gh-login <ID>  操作を先に書いてもよい。rm は確認してから消し、-y で確認を省く
mvm sync <ID>                         手元の作業ツリーを、コミットしていない変更も含めて VM の ~/work/<リポジトリ> に反映する
mvm exec <ID> [--sync] -- <コマンド>  VM の中の、手元のカレントディレクトリに対応する場所でコマンドを実行する
mvm port <ID> <ポート> [手元のポート]  VM のポートを手元の 127.0.0.1 に転送する
mvm up --no-login                     起動してもログインせず、ID だけを標準出力に出す（端末がないときはこれが既定）
```

bin/mvm は、zsh 以外のシェルやスクリプトから mvm を呼ぶためのラッパーです。

Coding Agent から使う

skills/mvm/SKILL.md は、Claude Code などの coding agent に mvm の使い方を教えるスキルです。ln -s "$PWD/skills/mvm" ~/.claude/skills/mvm でインストールすると、agent は「VM でテストして」のような依頼を受けて、mvm up --no-login で VM を用意し、mvm exec <ID> --sync -- '<コマンド>' で手元の未コミットの変更ごと VM で実行するようになります。VM を消す mvm rm は、agent が自分の判断では実行せず、ユーザーに確認するように書いてあります。

sync は一方向です。VM の中で生まれたファイルは手元に戻らないので、出力で受け取るか、VM から push します。sync は、その VM のチェックアウトにあるコミットしていない変更を捨てます。git が無視するファイル（node_modules やビルド成果物）は残します。

TAB 補完

mvm のあとは TAB を押していけば一通りの操作ができます。最初の TAB で選択メニューが開き、TAB を押すたびに次の候補へ移り、Enter で確定します。

mvm <TAB> では、up、ls、stop などの操作と、生きている VM の一覧が出ます。VM の候補には、状態、イメージ、起動時刻、残り時間、clone したリポジトリが並び、RUNNING は緑、SUSPENDED は黄色で表示されます。VM を選んでもう一度 TAB を押すと、その VM の状態でできる操作だけが出ます。RUNNING なら ssh、stop、clone、gh-login、rm、-- の順で、SUSPENDED なら resume が先頭です。mvm stop <TAB> では RUNNING の VM だけ、mvm resume <TAB> では SUSPENDED の VM だけが出ます。mvm up -i <TAB> ではイメージ名と最新バージョンが出ます。

ID を打つ必要はありません。mvm hello<TAB> のようにリポジトリ名を打てば、そのリポジトリを clone した VM の ID に置き換わります。状態の SUSP や、ID の一部の c7a9 でも同じです。

コマンドラインが完成した状態で TAB を押すと、Enter で何が起きるかがプロンプトの下に出ます。たとえば mvm stop <ID> では、suspend する VM の状態と残り時間が出ます。-a や -y のようなフラグは、- を打つまで候補に出しません。TAB を連打しても rm の確認を飛ばす -y が勝手に入らないようにするためです。

mvm と打った時点で、VM とイメージの一覧をバックグラウンドで取りにいきます。そのため TAB を押すと、AWS を待たずに候補が出ます。一覧は VM が 10 秒、イメージが 60 秒のあいだ ~/.cache/mvm に置いて使い回し、mvm up、stop、resume、rm を実行すると捨てます。

TAB にはもともとの割り当て（zeno.zsh や fzf-tab など）をそのまま残し、mvm の行でもそれを経由して補完します。プラグインがあとから TAB を割り当て直したり、compinit を zsh-defer で遅らせたりしていても、プロンプトを出すたびに割り当てを確かめ直します。TAB の割り当てに触れてほしくないときは MVM_NO_ZLE=1、メニューや色の zstyle が要らないときは MVM_NO_STYLES=1 を、mvm.zsh を読み込む前に設定してください。

デモの動画は demo/demo.tape を vhs で収録し、demo/make.zsh で字幕を焼き込んで docs/assets に書き出しています。

tests/complete.zsh は TAB を押したときに出る候補を、tests/zle.zsh はキー入力のあとのコマンドラインと Enter の予告を、疑似端末で確かめるスクリプトです。

```bash
tests/complete.zsh 'mvm ' 'mvm stop '
tests/zle.zsh $'mvm \t\t\r' $'mvm stop \t\t'
MVM_TEST_REAL=1 tests/zle.zsh $'mvm hello\t'   # ふだんの ~/.zshrc で試す
MVM_TEST_STUB=1 tests/zle.zsh $'mvm stop \t'    # AWS を呼ばず、tests/stub/aws の架空の VM で試す
MVM_TEST_POST='source /opt/homebrew/opt/fzf/shell/completion.zsh' MVM_TEST_STUB=1 tests/zle.zsh $'ls /tm\t'
```

tests/stub/aws は AWS_SLEEP=秒数 で応答を遅らせ、AWS_FAIL=1 で認証切れのように失敗します。AWS が遅くても一覧の取得は同時に 1 本しか走らず、10 秒で打ち切ります。失敗したときは、VM がないのではなく aws が失敗したと補完に出します。

mvm up を git リポジトリの中で実行すると、origin を HTTPS に直して VM の ~/work/<名前> に clone し、手元と同じブランチを checkout します。origin にまだないコミットは git bundle にして ssh で送り、VM 側に取り込みます。コミットしていない変更は持っていきません。VM に同じディレクトリがすでにあるときは fetch だけして、VM 側のブランチは動かしません。

GitHub のトークン

mvm up と mvm gh-login は、MVM_GH_TOKEN_CMD の出力を ssh の標準入力で VM に流し、git credential approve で git の credential-cache に入れます。トークンはこのデーモンのメモリに 8 時間置かれます。コマンドライン引数、環境変数のファイル、~/.config/gh には書きません。VM の gh はラッパーで、実行のたびに credential-cache からトークンを取り出し、その gh プロセスの環境変数 GH_TOKEN に入れて渡します。

注意が 2 つあります。VM の中で動くプロセスは、Claude Code を含めてこのトークンで GitHub を操作できます。gh auth token はアカウント全体に効くので、VM 用には対象リポジトリに絞った fine-grained PAT を MVM_GH_TOKEN_CMD で渡すことをおすすめします。もう 1 つ、VM が suspend されるとメモリの内容はプラットフォーム側に保存されるので、デーモン内のトークンもそこに含まれます。

VM の中の権限

dev ユーザーはパスワードなしで sudo できるので、VM の中で動くコードは root と同じことができます。実行ロールの一時認証情報は VM 内の IMDS から誰でも取れ、Bedrock の呼び出しとロググループへの書き込みに使えます。Claude Code や Codex がプロンプトインジェクションを受ければ、GitHub のトークンも実行ロールの認証情報も持ち出されうる前提で、VM に置くものと渡すトークンの範囲を決めてください。

VM に入るには 2 つが要ります。create-microvm-auth-token を呼べる IAM の権限と、~/.ssh/mvm_ed25519 の秘密鍵です。ライフサイクルフックのポート 9000 は認証なしで待ち受けていて、ポート 9000 用のトークンを発行すればエンドポイント経由でも届くことを確かめました。そのため mvm-agent は、公開鍵を書き込む /run を最初の 1 回しか受け付けません。最初の /run が不正な内容でも閉じたままにし、2 回目以降は 409 を返します。runHookPayload から受け取る環境変数は AWS_REGION、AWS_DEFAULT_REGION、TZ だけです。runHookPayload は RunMicrovm の引数として CloudTrail に残るので、秘密は入れません。

実行ロールの信頼ポリシーは aws:SourceAccount だけで絞っています。サービスが渡す aws:SourceArn の形式を確かめられなかったためです。同じアカウントで iam:PassRole を持つ人は、このロールを別の Lambda に渡せます。

接続の仕組み

ssh は ProxyCommand で bin/mvm-proxy を呼びます。mvm-proxy は get-microvm でエンドポイントを引き、create-microvm-auth-token でポート 2222 に限った 60 分のトークンを発行して、websocat で wss://<エンドポイント>/ につなぎます。エンドポイントとトークンは ~/.cache/mvm/<ID>/ にパーミッション 600 で置き、残りが 10 分を切ったら発行し直します。websocat はトークンを引数でしか受け取らないので、接続中は手元の ps に見えます。ControlMaster で接続を 120 秒使い回すので、2 回目以降の ssh はトークンの発行も WebSocket の接続もしません。

VM の寿命は最長 8 時間です。MVM_IDLE_SECONDS のあいだ通信がないと suspend され、ssh でつなぐと自動で再開します。suspend のまま 1 時間たつと terminate されます。~/work の外も含めて VM の中身はすべて消えるので、成果は push してください。

イメージを作り直すたびにバージョンが 1 つ増え、古いバージョンも残って保存料金がかかります。使っていないバージョンは次のように消します。

```bash
aws lambda-microvms delete-microvm-image-version --region ap-northeast-1 \
  --image-identifier arn:aws:lambda:ap-northeast-1:<アカウント ID>:microvm-image:mvm --image-version 1.0
```
