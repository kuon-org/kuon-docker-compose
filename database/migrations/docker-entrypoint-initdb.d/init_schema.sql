-- スキーマ作成
CREATE SCHEMA IF NOT EXISTS knowledge;
SET search_path TO knowledge;

create table knowledge.kuon_migrations (
    name text not null,
    applied_at timestamp(6) with time zone default CURRENT_TIMESTAMP not null,
    primary key (name)
);

CREATE TABLE IF NOT EXISTS server_settings (
    key VARCHAR(100) PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE knowledge.server_settings IS 'Kuonインスタンス全体のサーバ設定を管理するテーブル';

COMMENT ON COLUMN knowledge.server_settings.key IS 'サーバ設定の識別子';
COMMENT ON COLUMN knowledge.server_settings.value IS 'サーバ設定の値';
COMMENT ON COLUMN knowledge.server_settings.updated_at IS 'サーバ設定が最後に更新された日時';

-- users テーブル
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    username VARCHAR(50) UNIQUE,
    display_name VARCHAR(100),
    email VARCHAR(255),
    avatar_url TEXT,
    bio TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,
    last_login_at TIMESTAMP,
    created_by UUID
);


COMMENT ON TABLE users IS 'ユーザ情報';
COMMENT ON COLUMN users.id IS 'ユーザID';
COMMENT ON COLUMN users.username IS 'ログイン用ユーザ名';
COMMENT ON COLUMN users.display_name IS '表示名';
COMMENT ON COLUMN users.email IS 'メールアドレス';
COMMENT ON COLUMN users.avatar_url IS 'アバターURL';
COMMENT ON COLUMN users.bio IS 'プロフィール文';
COMMENT ON COLUMN users.created_at IS '作成日時';
COMMENT ON COLUMN users.updated_at IS '更新日時';
COMMENT ON COLUMN users.is_active IS '有効フラグ';
COMMENT ON COLUMN users.last_login_at IS '最終ログイン日時';
COMMENT ON COLUMN users.created_by IS '作成者ユーザID';

-- groups / user_groups
CREATE TABLE IF NOT EXISTS groups (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    name VARCHAR(100) NOT NULL,
    slug VARCHAR(50) NOT NULL UNIQUE,
    display_name VARCHAR(100) NOT NULL,
    description TEXT,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_groups (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL DEFAULT 'member',
    joined_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (user_id, group_id),
    CONSTRAINT user_groups_role_check CHECK (role IN ('owner', 'admin', 'member'))
);

CREATE INDEX IF NOT EXISTS idx_user_groups_group_id ON user_groups(group_id);

CREATE TABLE IF NOT EXISTS group_follows (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (user_id, group_id)
);

CREATE INDEX IF NOT EXISTS idx_group_follows_group_id ON group_follows(group_id);

-- server_events
CREATE TABLE IF NOT EXISTS knowledge.server_events (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    category VARCHAR(30) NOT NULL DEFAULT 'system',
    event_type VARCHAR(100) NOT NULL,
    level VARCHAR(10) NOT NULL,
    source VARCHAR(100),
    message TEXT NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    actor_user_id UUID REFERENCES knowledge.users(id),
    ip_address INET,
    subject_type VARCHAR(50),
    subject_id UUID,
    before_data JSONB,
    after_data JSONB,
    correlation_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT server_events_category_check CHECK (category IN ('system', 'audit')),
    CONSTRAINT server_events_level_check CHECK (level IN ('info', 'warning', 'error'))
);

CREATE INDEX IF NOT EXISTS idx_server_events_category
    ON knowledge.server_events(category);
CREATE INDEX IF NOT EXISTS idx_server_events_event_type
    ON knowledge.server_events(event_type);
CREATE INDEX IF NOT EXISTS idx_server_events_level
    ON knowledge.server_events(level);
CREATE INDEX IF NOT EXISTS idx_server_events_created_at
    ON knowledge.server_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_server_events_correlation_id
    ON knowledge.server_events(correlation_id)
    WHERE correlation_id IS NOT NULL;

COMMENT ON TABLE knowledge.server_events IS 'Kuonサーバ内部で発生した運用・監査イベント';
COMMENT ON COLUMN knowledge.server_events.category IS 'イベントカテゴリ(system/audit)';
COMMENT ON COLUMN knowledge.server_events.event_type IS 'イベント種別';
COMMENT ON COLUMN knowledge.server_events.level IS '重要度(info/warning/error)';
COMMENT ON COLUMN knowledge.server_events.source IS 'イベント発生元コンポーネント';
COMMENT ON COLUMN knowledge.server_events.message IS 'イベントの概要メッセージ';
COMMENT ON COLUMN knowledge.server_events.metadata IS 'イベント固有の補足情報(JSONB)。機密情報は保存しない';
COMMENT ON COLUMN knowledge.server_events.actor_user_id IS 'イベントを発生させたユーザID。システムイベントではNULL可';
COMMENT ON COLUMN knowledge.server_events.ip_address IS 'イベント発生元IPアドレス';
COMMENT ON COLUMN knowledge.server_events.subject_type IS '操作対象リソース種別。将来の監査ログ/Revertで利用';
COMMENT ON COLUMN knowledge.server_events.subject_id IS '操作対象リソースID。将来の監査ログ/Revertで利用';
COMMENT ON COLUMN knowledge.server_events.before_data IS '変更前データ(JSONB)。将来の監査ログ/Revertで利用';
COMMENT ON COLUMN knowledge.server_events.after_data IS '変更後データ(JSONB)。将来の監査ログ/Revertで利用';
COMMENT ON COLUMN knowledge.server_events.correlation_id IS '一連の処理を関連付ける相関ID';
COMMENT ON COLUMN knowledge.server_events.created_at IS 'イベント発生日時';

-- user_sessions
CREATE TABLE IF NOT EXISTS knowledge.user_sessions (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id UUID NOT NULL REFERENCES knowledge.users(id) ON DELETE CASCADE,
    refresh_token TEXT NOT NULL UNIQUE,
    ip_address TEXT,
    user_agent TEXT,
    device_name TEXT,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    last_used_at TIMESTAMP DEFAULT NOW()
);

-- ===== インデックス =====
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON knowledge.user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_refresh_token ON knowledge.user_sessions(refresh_token);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expires_at ON knowledge.user_sessions(expires_at);

COMMENT ON TABLE knowledge.user_sessions IS 'ユーザセッション情報（リフレッシュトークン管理用）';
COMMENT ON COLUMN knowledge.user_sessions.id IS 'セッションID';
COMMENT ON COLUMN knowledge.user_sessions.user_id IS 'ユーザID';
COMMENT ON COLUMN knowledge.user_sessions.refresh_token IS 'リフレッシュトークン（ハッシュ化して保存することを推奨）';
COMMENT ON COLUMN knowledge.user_sessions.ip_address IS 'ログイン時のIPアドレス';
COMMENT ON COLUMN knowledge.user_sessions.user_agent IS 'ブラウザ・端末情報（User-Agent）';
COMMENT ON COLUMN knowledge.user_sessions.device_name IS '任意の端末名（ユーザ設定用）';
COMMENT ON COLUMN knowledge.user_sessions.expires_at IS 'リフレッシュトークンの有効期限';
COMMENT ON COLUMN knowledge.user_sessions.created_at IS 'セッション作成日時';
COMMENT ON COLUMN knowledge.user_sessions.last_used_at IS '最終利用日時（refresh時に更新）';

-- local_accounts
CREATE TABLE IF NOT EXISTS local_accounts (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id UUID REFERENCES users(id),
    email VARCHAR(255),
    password_hash TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    is_verified BOOLEAN DEFAULT FALSE
);

COMMENT ON TABLE local_accounts IS 'ローカルアカウント情報';
COMMENT ON COLUMN local_accounts.id IS 'ローカルアカウントID';
COMMENT ON COLUMN local_accounts.user_id IS '紐づくユーザID';
COMMENT ON COLUMN local_accounts.email IS 'メールアドレス';
COMMENT ON COLUMN local_accounts.password_hash IS 'パスワードハッシュ';
COMMENT ON COLUMN local_accounts.created_at IS '作成日時';
COMMENT ON COLUMN local_accounts.updated_at IS '更新日時';
COMMENT ON COLUMN local_accounts.is_verified IS 'メール確認済みフラグ';

-- identity_providers
CREATE TABLE IF NOT EXISTS identity_providers (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    provider_name VARCHAR(50) NOT NULL UNIQUE,      -- 内部識別名（例: google, github）
    display_name VARCHAR(50) NOT NULL,       -- UI表示名
    provider_type VARCHAR(20) NOT NULL,      -- 認証方式 (OIDC, SAML, LDAP, OAuth)
    description TEXT,
    logo_url TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

COMMENT ON TABLE identity_providers IS '外部IdP情報';
COMMENT ON COLUMN identity_providers.id IS 'IdP ID';
COMMENT ON COLUMN identity_providers.provider_name IS 'プロバイダ名（内部識別用）';
COMMENT ON COLUMN identity_providers.display_name IS '表示名';
COMMENT ON COLUMN identity_providers.provider_type IS '認証方式(OIDC/SAML/LDAP/OAuth等)';
COMMENT ON COLUMN identity_providers.description IS '説明';
COMMENT ON COLUMN identity_providers.logo_url IS 'ロゴURL';
COMMENT ON COLUMN identity_providers.created_at IS '作成日時';
COMMENT ON COLUMN identity_providers.updated_at IS '更新日時';

-- idp_configurations
CREATE TABLE IF NOT EXISTS idp_configurations (
    provider_id UUID PRIMARY KEY REFERENCES identity_providers(id),
    config JSONB NOT NULL DEFAULT '{}'::jsonb,   -- 方式固有設定をJSONBで保持
    button_color VARCHAR(20),                     -- ログインボタン背景色
    text_color VARCHAR(20),                       -- ログインボタン文字色
    is_active BOOLEAN DEFAULT FALSE,              -- 有効フラグ
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    last_tested_at TIMESTAMP,
    created_by UUID
);

COMMENT ON TABLE idp_configurations IS 'IdP接続設定';
COMMENT ON COLUMN idp_configurations.provider_id IS '外部IdP ID';
COMMENT ON COLUMN idp_configurations.config IS '方式固有設定 (JSON形式)';
COMMENT ON COLUMN idp_configurations.button_color IS 'ログインボタン背景色';
COMMENT ON COLUMN idp_configurations.text_color IS 'ログインボタン文字色';
COMMENT ON COLUMN idp_configurations.is_active IS '有効フラグ';
COMMENT ON COLUMN idp_configurations.created_at IS '作成日時';
COMMENT ON COLUMN idp_configurations.updated_at IS '更新日時';
COMMENT ON COLUMN idp_configurations.last_tested_at IS '最後の接続テスト日時';
COMMENT ON COLUMN idp_configurations.created_by IS '作成者ユーザID';

-- user_identities
CREATE TABLE IF NOT EXISTS user_identities (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id UUID REFERENCES users(id) NOT NULL,
    provider_id UUID REFERENCES identity_providers(id) NOT NULL,
    provider_uid VARCHAR(255) NOT NULL,        -- IdP側ユーザID
    email VARCHAR(255),
    token_data JSONB DEFAULT '{}'::jsonb,      -- OAuthアクセストークン等をJSONBで保持
    linked_at TIMESTAMP DEFAULT NOW(),
    last_login_at TIMESTAMP
);

COMMENT ON TABLE user_identities IS 'ユーザとIdPの紐付け情報';
COMMENT ON COLUMN user_identities.id IS 'ID';
COMMENT ON COLUMN user_identities.user_id IS 'ユーザID';
COMMENT ON COLUMN user_identities.provider_id IS '外部IdP ID';
COMMENT ON COLUMN user_identities.provider_uid IS 'IdP側ユーザID';
COMMENT ON COLUMN user_identities.email IS 'メールアドレス';
COMMENT ON COLUMN user_identities.token_data IS '方式固有トークン情報(JSONB)';
COMMENT ON COLUMN user_identities.linked_at IS '紐付け日時';
COMMENT ON COLUMN user_identities.last_login_at IS '最終ログイン日時';

-- roles
CREATE TABLE IF NOT EXISTS roles (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    name VARCHAR(50) UNIQUE,
    display_name VARCHAR(50),
    description TEXT,
    is_builtin BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

COMMENT ON TABLE roles IS 'ユーザ権限ロール';
COMMENT ON COLUMN roles.id IS 'ロールID';
COMMENT ON COLUMN roles.name IS '内部識別名';
COMMENT ON COLUMN roles.display_name IS '表示名';
COMMENT ON COLUMN roles.description IS '説明';
COMMENT ON COLUMN roles.is_builtin IS 'Kuon標準の組み込みロールかどうか';
COMMENT ON COLUMN roles.created_at IS '作成日時';
COMMENT ON COLUMN roles.updated_at IS '更新日時';

-- permissions
CREATE TABLE IF NOT EXISTS permissions (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    key VARCHAR(100) NOT NULL UNIQUE,
    display_name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE permissions IS 'Kuonで利用可能な操作権限のマスタ';
COMMENT ON COLUMN permissions.id IS 'Permission ID';
COMMENT ON COLUMN permissions.key IS 'Permissionの内部識別キー';
COMMENT ON COLUMN permissions.display_name IS '管理画面に表示するPermission名';
COMMENT ON COLUMN permissions.category IS 'Permissionの機能カテゴリ';
COMMENT ON COLUMN permissions.description IS 'Permissionの説明';
COMMENT ON COLUMN permissions.created_at IS '作成日時';

-- role_permissions
CREATE TABLE IF NOT EXISTS role_permissions (
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (role_id, permission_id)
);

COMMENT ON TABLE role_permissions IS 'ロールとPermissionの紐付け';
COMMENT ON COLUMN role_permissions.role_id IS 'ロールID';
COMMENT ON COLUMN role_permissions.permission_id IS 'Permission ID';
COMMENT ON COLUMN role_permissions.created_at IS '紐付け日時';

CREATE INDEX IF NOT EXISTS idx_role_permissions_permission_id
    ON role_permissions(permission_id);

-- user_roles
CREATE TABLE IF NOT EXISTS user_roles (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id UUID REFERENCES users(id),
    role_id UUID REFERENCES roles(id),
    assigned_at TIMESTAMP DEFAULT NOW(),
    assigned_by UUID
);

COMMENT ON TABLE user_roles IS 'ユーザに付与されたロール情報';
COMMENT ON COLUMN user_roles.id IS 'ID';
COMMENT ON COLUMN user_roles.user_id IS 'ユーザID';
COMMENT ON COLUMN user_roles.role_id IS 'ロールID';
COMMENT ON COLUMN user_roles.assigned_at IS '付与日時';
COMMENT ON COLUMN user_roles.assigned_by IS '付与者ユーザID';

-- articles
CREATE TABLE IF NOT EXISTS articles (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id UUID REFERENCES users(id),
    group_id UUID REFERENCES groups(id) ON DELETE SET NULL,
    title VARCHAR(255),
    raw_content TEXT,
    last_published_raw_content TEXT,
    render_content TEXT,
    summary TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    status VARCHAR(10),
    is_published BOOLEAN DEFAULT FALSE,
    is_private BOOLEAN DEFAULT FALSE,
    visibility VARCHAR(10) NOT NULL DEFAULT 'unlisted',
    is_deleted BOOLEAN DEFAULT FALSE,
    like_count INT DEFAULT 0,
    view_count INT DEFAULT 0,
    stock_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    CONSTRAINT articles_visibility_check CHECK (visibility IN ('public', 'unlisted', 'private', 'members')),
    CONSTRAINT articles_members_group_check CHECK (visibility <> 'members' OR group_id IS NOT NULL)
);

COMMENT ON TABLE articles IS '記事';
COMMENT ON COLUMN articles.id IS '記事ID';
COMMENT ON COLUMN articles.user_id IS '作成者ユーザID';
COMMENT ON COLUMN articles.title IS 'タイトル';
COMMENT ON COLUMN articles.raw_content IS '生コンテンツ';
COMMENT ON COLUMN articles.last_published_raw_content IS '最後に公開した時点の生コンテンツ';
COMMENT ON COLUMN articles.render_content IS 'レンダリング済みコンテンツ';
COMMENT ON COLUMN articles.summary IS '要約';
COMMENT ON COLUMN articles.created_at IS '作成日時';
COMMENT ON COLUMN articles.updated_at IS '更新日時';
COMMENT ON COLUMN articles.status IS 'ステータス';
COMMENT ON COLUMN articles.is_published IS '公開フラグ';
COMMENT ON COLUMN articles.is_private IS '非公開フラグ';
COMMENT ON COLUMN articles.is_deleted IS '論理削除フラグ';
COMMENT ON COLUMN articles.like_count IS 'いいね数';
COMMENT ON COLUMN articles.view_count IS '閲覧数';
COMMENT ON COLUMN articles.stock_count IS 'この記事が保存されているストックリストの総数';
COMMENT ON COLUMN articles.comment_count IS 'コメント数';

CREATE INDEX IF NOT EXISTS idx_articles_group_id ON articles(group_id);

-- stock_lists テーブル
CREATE TABLE IF NOT EXISTS stock_lists (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    -- 'public' (公開), 'limited' (限定公開), 'private' (非公開)
    visibility VARCHAR(10) DEFAULT 'private', 
    is_system BOOLEAN DEFAULT FALSE,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
COMMENT ON TABLE stock_lists IS 'ストックリスト';
COMMENT ON COLUMN stock_lists.id IS 'リストID';
COMMENT ON COLUMN stock_lists.user_id IS '所有ユーザID';
COMMENT ON COLUMN stock_lists.name IS 'リスト名';
COMMENT ON COLUMN stock_lists.description IS 'リストの説明';
COMMENT ON COLUMN stock_lists.visibility IS '公開範囲設定';
COMMENT ON COLUMN stock_lists.is_system IS 'アプリ側が作成';
COMMENT ON COLUMN stock_lists.is_default IS '自動保存先フラグ';
COMMENT ON COLUMN stock_lists.created_at IS '作成日時';
COMMENT ON COLUMN stock_lists.updated_at IS '更新日時';


-- stock_items テーブル (リストの中身)
CREATE TABLE IF NOT EXISTS stock_items (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    stock_list_id UUID REFERENCES stock_lists(id) ON DELETE CASCADE NOT NULL,
    article_id UUID REFERENCES articles(id) ON DELETE CASCADE NOT NULL,
    sort_order INT DEFAULT 0, 
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE (stock_list_id, article_id)
);

COMMENT ON TABLE stock_items IS 'ストックリスト内の各記事';
COMMENT ON COLUMN stock_items.stock_list_id IS '所属するリストのID';
COMMENT ON COLUMN stock_items.article_id IS '保存された記事ID';
COMMENT ON COLUMN stock_items.sort_order IS 'リスト内での並び順';
COMMENT ON COLUMN stock_items.created_at IS '作成日時';

-- tags
CREATE TABLE IF NOT EXISTS tags (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    name VARCHAR(50),
    slug VARCHAR(50) UNIQUE,
    avatar_url TEXT,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

COMMENT ON TABLE tags IS 'タグ';
COMMENT ON COLUMN tags.id IS 'タグID';
COMMENT ON COLUMN tags.name IS 'タグ名';
COMMENT ON COLUMN tags.slug IS 'スラッグ';
COMMENT ON COLUMN tags.avatar_url IS 'タグアイコン';
COMMENT ON COLUMN tags.description IS '説明';
COMMENT ON COLUMN tags.created_at IS '作成日時';

-- stock_tags
CREATE TABLE IF NOT EXISTS stock_list_tags (
    stock_list_id UUID REFERENCES stock_lists(id) ON DELETE CASCADE,
    tag_id UUID REFERENCES tags(id) ON DELETE CASCADE,
    attached_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (stock_list_id, tag_id)
);
COMMENT ON TABLE stock_list_tags IS 'ストックリストとタグの紐づけ';
COMMENT ON COLUMN stock_list_tags.stock_list_id IS 'ストックリストID';
COMMENT ON COLUMN stock_list_tags.tag_id IS 'タグID';
COMMENT ON COLUMN stock_list_tags.attached_at IS '紐付け日時';

-- stock_list_likes
CREATE TABLE IF NOT EXISTS stock_list_likes (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    stock_list_id UUID REFERENCES stock_lists(id) ON DELETE CASCADE,
    created_at  TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (user_id, stock_list_id)
);

COMMENT ON TABLE stock_list_likes IS 'ストックリストへのいいね';
COMMENT ON COLUMN stock_list_likes.user_id IS 'ユーザID';
COMMENT ON COLUMN stock_list_likes.stock_list_id IS 'ストックリストID';
COMMENT ON COLUMN stock_list_likes.created_at IS '作成日時';

-- article_tags
CREATE TABLE IF NOT EXISTS article_tags (
    article_id UUID REFERENCES articles(id),
    tag_id UUID REFERENCES tags(id),
    attached_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (article_id, tag_id)
);

COMMENT ON TABLE article_tags IS '記事とタグの紐付け';
COMMENT ON COLUMN article_tags.article_id IS '記事ID';
COMMENT ON COLUMN article_tags.tag_id IS 'タグID';
COMMENT ON COLUMN article_tags.attached_at IS '紐付け日時';

-- article_likes
CREATE TABLE IF NOT EXISTS article_likes (
    article_id UUID REFERENCES articles(id),
    user_id UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (article_id, user_id)
);

COMMENT ON TABLE article_likes IS '記事へのいいね';
COMMENT ON COLUMN article_likes.article_id IS '記事ID';
COMMENT ON COLUMN article_likes.user_id IS 'ユーザID';
COMMENT ON COLUMN article_likes.created_at IS '作成日時';

-- article_views
CREATE TABLE IF NOT EXISTS article_views (
    article_id UUID REFERENCES articles(id),
    user_id UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (article_id, user_id)
);

COMMENT ON TABLE article_views IS '記事閲覧履歴';
COMMENT ON COLUMN article_views.article_id IS '記事ID';
COMMENT ON COLUMN article_views.user_id IS 'ユーザID';
COMMENT ON COLUMN article_views.created_at IS '作成日時';

-- comments
CREATE TABLE IF NOT EXISTS comments (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    article_id UUID REFERENCES articles(id),
    user_id UUID REFERENCES users(id),
    body TEXT,
    parent_comment_id UUID REFERENCES comments(id),
    like_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    is_deleted BOOLEAN DEFAULT FALSE
);

COMMENT ON TABLE comments IS 'コメント';
COMMENT ON COLUMN comments.id IS 'コメントID';
COMMENT ON COLUMN comments.article_id IS '記事ID';
COMMENT ON COLUMN comments.user_id IS 'ユーザID';
COMMENT ON COLUMN comments.body IS 'コメント本文';
COMMENT ON COLUMN comments.parent_comment_id IS '親コメントID';
COMMENT ON COLUMN comments.like_count IS 'いいね数';
COMMENT ON COLUMN comments.created_at IS '作成日時';
COMMENT ON COLUMN comments.updated_at IS '更新日時';
COMMENT ON COLUMN comments.is_deleted IS '削除フラグ';

-- comment_likes
CREATE TABLE IF NOT EXISTS comment_likes (
    comment_id UUID REFERENCES comments(id),
    user_id UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (comment_id, user_id)
);

COMMENT ON TABLE comment_likes IS 'コメントいいね';
COMMENT ON COLUMN comment_likes.comment_id IS 'コメントID';
COMMENT ON COLUMN comment_likes.user_id IS 'ユーザID';
COMMENT ON COLUMN comment_likes.created_at IS '作成日時';

-- user_follows
CREATE TABLE IF NOT EXISTS user_follows (
    follower_id UUID REFERENCES users(id),
    followee_id UUID REFERENCES users(id),
    followed_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (follower_id, followee_id)
);

COMMENT ON TABLE user_follows IS 'ユーザ間のフォロー関係';
COMMENT ON COLUMN user_follows.follower_id IS 'フォローする側のユーザID';
COMMENT ON COLUMN user_follows.followee_id IS 'フォローされる側のユーザID';
COMMENT ON COLUMN user_follows.followed_at IS 'フォロー日時';

-- upload_images テーブル (汎用版)
CREATE TABLE IF NOT EXISTS upload_images (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id UUID REFERENCES users(id) NOT NULL,
    category VARCHAR(20) NOT NULL,            -- 'article', 'avatar', 'system' 等
    original_name TEXT NOT NULL,
    mime_type VARCHAR(100),
    size_bytes INT,
    created_at TIMESTAMP DEFAULT NOW()
);

COMMENT ON TABLE upload_images IS 'アップロード画像管理';
COMMENT ON COLUMN upload_images.id IS '画像ID（実ファイル名に使用）';
COMMENT ON COLUMN upload_images.user_id IS 'ユーザID';
COMMENT ON COLUMN upload_images.category IS '用途（article/avatar等）';
COMMENT ON COLUMN upload_images.original_name IS 'オリジナルファイル名';
COMMENT ON COLUMN upload_images.mime_type IS 'MIMEタイプ（例: image/png, image/jpeg）';
COMMENT ON COLUMN upload_images.size_bytes IS 'ファイルサイズ（バイト単位）';
COMMENT ON COLUMN upload_images.created_at IS 'アップロード日時';



-- user_notifications
CREATE TABLE IF NOT EXISTS user_notifications (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id UUID REFERENCES users(id),
    type VARCHAR(50),                         -- 通知種別 (article.comment.created, comment.reply.created, article.published, user.followed, etc.)
    title TEXT,
    message TEXT,
    reference_id UUID,                        -- 関連する記事・コメント・ユーザのID
    reference_type VARCHAR(30),               -- 参照先種別(article/comment/user等)
    reasons JSONB NOT NULL DEFAULT '[]'::jsonb, -- 同一通知が生成された理由の一覧
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);

COMMENT ON TABLE user_notifications IS 'ユーザ通知情報';
COMMENT ON COLUMN user_notifications.user_id IS '通知対象ユーザID';
COMMENT ON COLUMN user_notifications.type IS '通知種別';
COMMENT ON COLUMN user_notifications.title IS '通知タイトル';
COMMENT ON COLUMN user_notifications.message IS '通知メッセージ';
COMMENT ON COLUMN user_notifications.reference_id IS '関連リソースID';
COMMENT ON COLUMN user_notifications.reference_type IS '通知の参照先種別(article/comment/user等)';
COMMENT ON COLUMN user_notifications.reasons IS '同一通知が生成された理由の一覧(JSON配列)';
COMMENT ON COLUMN user_notifications.is_read IS '既読フラグ';
COMMENT ON COLUMN user_notifications.created_at IS '通知作成日時';

-- 同一ユーザ・同一記事の公開通知は1件に集約する
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_notifications_article_published
    ON knowledge.user_notifications(user_id, reference_type, reference_id)
    WHERE type = 'article.published';

-- user_settings
CREATE TABLE IF NOT EXISTS user_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id),
    language VARCHAR(10) DEFAULT 'ja',        -- 表示言語
    theme VARCHAR(20) DEFAULT 'light',        -- テーマ(light/dark)
    notify_on_like BOOLEAN DEFAULT TRUE,
    notify_on_comment BOOLEAN DEFAULT TRUE,
    notify_on_follow BOOLEAN DEFAULT TRUE,
    notify_on_article_comment BOOLEAN DEFAULT TRUE,
    notify_on_comment_reply BOOLEAN DEFAULT TRUE,
    notify_on_followed_tag_article BOOLEAN DEFAULT TRUE,
    notify_on_followed_user_article BOOLEAN DEFAULT TRUE,
    notify_on_followed_group_article BOOLEAN DEFAULT TRUE,
    notify_on_user_follow BOOLEAN DEFAULT TRUE,
    notify_via_email BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

COMMENT ON TABLE user_settings IS 'ユーザ個別設定';
COMMENT ON COLUMN user_settings.user_id IS 'ユーザID';
COMMENT ON COLUMN user_settings.language IS '表示言語コード';
COMMENT ON COLUMN user_settings.theme IS 'テーマ設定';
COMMENT ON COLUMN user_settings.notify_on_like IS 'いいね通知';
COMMENT ON COLUMN user_settings.notify_on_comment IS 'コメント通知';
COMMENT ON COLUMN user_settings.notify_on_follow IS 'フォロー通知';
COMMENT ON COLUMN user_settings.notify_on_article_comment IS '自分の記事へのコメントをアプリ内通知するか';
COMMENT ON COLUMN user_settings.notify_on_comment_reply IS '自分のコメントへの返信をアプリ内通知するか';
COMMENT ON COLUMN user_settings.notify_on_followed_tag_article IS 'フォロー中タグの新着記事をアプリ内通知するか';
COMMENT ON COLUMN user_settings.notify_on_followed_user_article IS 'フォロー中ユーザの新着記事をアプリ内通知するか';
COMMENT ON COLUMN user_settings.notify_on_user_follow IS '他ユーザからフォローされたときにアプリ内通知するか';
COMMENT ON COLUMN user_settings.notify_via_email IS 'メール通知を有効にするか';
COMMENT ON COLUMN user_settings.created_at IS '作成日時';
COMMENT ON COLUMN user_settings.updated_at IS '更新日時';

-- user_security
CREATE TABLE IF NOT EXISTS user_security (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  totp_secret TEXT,
  is_2fa_enabled BOOLEAN DEFAULT false
);

COMMENT ON TABLE user_security IS 'ユーザのセキュリティ設定';
COMMENT ON COLUMN user_security.user_id IS 'ユーザID';
COMMENT ON COLUMN user_security.totp_secret IS 'TOTPシークレット';
COMMENT ON COLUMN user_security.is_2fa_enabled IS '2FA有効化フラグ';

-- user_api_keys
CREATE TABLE IF NOT EXISTS knowledge.user_api_keys (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id UUID NOT NULL REFERENCES knowledge.users(id) ON DELETE CASCADE,

    name VARCHAR(100) NOT NULL,              -- 管理用名称（例: CI用, CLI用）
    api_key_hash TEXT NOT NULL UNIQUE,       -- APIキーのハッシュ値（平文は保存しない）
    prefix VARCHAR(20) NOT NULL,             -- 表示用プレフィックス (例: sk_xxxxx)

    scopes JSONB DEFAULT '[]'::jsonb,        -- 権限スコープ ["read","write"]
    is_active BOOLEAN DEFAULT TRUE,          -- 有効フラグ

    last_used_at TIMESTAMP,                  -- 最終利用日時
    expires_at TIMESTAMP,                    -- 有効期限（NULLなら無期限）

    created_at TIMESTAMP DEFAULT NOW(),
    revoked_at TIMESTAMP,                    -- 失効日時
    created_by UUID                          -- 作成者
);

COMMENT ON TABLE knowledge.user_api_keys IS 'ユーザAPIキー';
COMMENT ON COLUMN knowledge.user_api_keys.id IS 'APIキーID';
COMMENT ON COLUMN knowledge.user_api_keys.user_id IS 'ユーザID';
COMMENT ON COLUMN knowledge.user_api_keys.name IS 'APIキー管理名';
COMMENT ON COLUMN knowledge.user_api_keys.api_key_hash IS 'APIキーのハッシュ値';
COMMENT ON COLUMN knowledge.user_api_keys.prefix IS '表示用プレフィックス';
COMMENT ON COLUMN knowledge.user_api_keys.scopes IS '権限スコープ(JSON配列)';
COMMENT ON COLUMN knowledge.user_api_keys.is_active IS '有効フラグ';
COMMENT ON COLUMN knowledge.user_api_keys.last_used_at IS '最終利用日時';
COMMENT ON COLUMN knowledge.user_api_keys.expires_at IS '有効期限';
COMMENT ON COLUMN knowledge.user_api_keys.created_at IS '作成日時';
COMMENT ON COLUMN knowledge.user_api_keys.revoked_at IS '失効日時';
COMMENT ON COLUMN knowledge.user_api_keys.created_by IS '作成者ユーザID';

-- index
CREATE INDEX IF NOT EXISTS idx_user_api_keys_user_id
    ON knowledge.user_api_keys(user_id);

CREATE INDEX IF NOT EXISTS idx_user_api_keys_active
    ON knowledge.user_api_keys(is_active);

CREATE INDEX IF NOT EXISTS idx_user_api_keys_expires
    ON knowledge.user_api_keys(expires_at);

-- user_avatars
CREATE TABLE IF NOT EXISTS knowledge.user_avatars (
    id uuid NOT NULL DEFAULT uuidv7(),
    user_id uuid NOT NULL,
    service_name character varying(50) NOT NULL,
    avatar_url text NOT NULL,
    source_url text,
    is_selected boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now(),
    CONSTRAINT user_avatars_pkey PRIMARY KEY (id),
    CONSTRAINT user_avatars_user_id_fkey FOREIGN KEY (user_id)
        REFERENCES knowledge.users (id) MATCH SIMPLE
        ON UPDATE NO ACTION ON DELETE CASCADE
);


COMMENT ON TABLE knowledge.user_avatars IS 'ユーザーのアバター画像管理';
COMMENT ON COLUMN knowledge.user_avatars.id IS 'アバターID';
COMMENT ON COLUMN knowledge.user_avatars.user_id IS 'ユーザーID';
COMMENT ON COLUMN knowledge.user_avatars.service_name IS '取得元サービス名 (discord, twitter, local等)';
COMMENT ON COLUMN knowledge.user_avatars.avatar_url IS 'サーバー内のローカル保存パス';
COMMENT ON COLUMN knowledge.user_avatars.source_url IS '外部サービスのオリジナルURL';
COMMENT ON COLUMN knowledge.user_avatars.is_selected IS '現在選択中フラグ';

-- tag_follows
CREATE TABLE IF NOT EXISTS knowledge.tag_follows (
    user_id UUID REFERENCES users(id),
    tag_id UUID REFERENCES tags(id),
    followed_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (user_id, tag_id)
);

COMMENT ON TABLE knowledge.tag_follows IS 'ユーザのフォローしているタグ';
COMMENT ON COLUMN knowledge.tag_follows.user_id IS 'フォローしたユーザ';
COMMENT ON COLUMN knowledge.tag_follows.tag_id IS 'フォローされたタグ';
COMMENT ON COLUMN knowledge.tag_follows.followed_at IS 'フォロー日時';

-- article_pickups
CREATE TABLE IF NOT EXISTS knowledge.article_pickups (
    user_id UUID REFERENCES users(id),
    article_id UUID REFERENCES articles(id),
    pickuped_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (user_id, article_id)
);

COMMENT ON TABLE knowledge.article_pickups IS 'ピックアップ記事';
COMMENT ON COLUMN knowledge.article_pickups.user_id IS 'ユーザID';
COMMENT ON COLUMN knowledge.article_pickups.article_id IS '記事ID';
COMMENT ON COLUMN knowledge.article_pickups.pickuped_at IS 'ピックアップ日時';




-- ---------------------------------
-- 記事の各種カウント更新関数
-- ---------------------------------
CREATE OR REPLACE FUNCTION knowledge.update_article_counts()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_TABLE_NAME = 'article_likes' THEN
        IF TG_OP = 'INSERT' THEN
            UPDATE knowledge.articles SET like_count = like_count + 1 WHERE id = NEW.article_id;
        ELSIF TG_OP = 'DELETE' THEN
            UPDATE knowledge.articles SET like_count = like_count - 1 WHERE id = OLD.article_id;
        END IF;
    ELSIF TG_TABLE_NAME = 'article_views' AND TG_OP = 'INSERT' THEN
        UPDATE knowledge.articles SET view_count = view_count + 1 WHERE id = NEW.article_id;
    ELSIF TG_TABLE_NAME = 'stock_items' THEN -- stock_items への変更を検知
        IF TG_OP = 'INSERT' THEN
            UPDATE knowledge.articles SET stock_count = stock_count + 1 WHERE id = NEW.article_id;
        ELSIF TG_OP = 'DELETE' THEN
            UPDATE knowledge.articles SET stock_count = stock_count - 1 WHERE id = OLD.article_id;
        END IF;
    ELSIF TG_TABLE_NAME = 'comments' THEN
        IF TG_OP = 'INSERT' THEN
            UPDATE knowledge.articles SET comment_count = comment_count + 1 WHERE id = NEW.article_id;
        ELSIF TG_OP = 'DELETE' THEN
            UPDATE knowledge.articles SET comment_count = comment_count - 1 WHERE id = OLD.article_id;
        END IF;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- コメントの like 更新関数
CREATE OR REPLACE FUNCTION knowledge.update_comment_like_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE knowledge.comments SET like_count = like_count + 1 WHERE id = NEW.comment_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE knowledge.comments SET like_count = like_count - 1 WHERE id = OLD.comment_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------
-- トリガー作成
-- ---------------------------------
-- 記事 likes
CREATE TRIGGER article_likes_insert
AFTER INSERT ON knowledge.article_likes
FOR EACH ROW
EXECUTE FUNCTION knowledge.update_article_counts();

CREATE TRIGGER article_likes_delete
AFTER DELETE ON knowledge.article_likes
FOR EACH ROW
EXECUTE FUNCTION knowledge.update_article_counts();

-- 記事 views
CREATE TRIGGER article_views_insert
AFTER INSERT ON knowledge.article_views
FOR EACH ROW
EXECUTE FUNCTION knowledge.update_article_counts();

-- ストック（リストへの追加/削除）
CREATE TRIGGER stock_items_insert
AFTER INSERT ON knowledge.stock_items
FOR EACH ROW
EXECUTE FUNCTION knowledge.update_article_counts();

CREATE TRIGGER stock_items_delete
AFTER DELETE ON knowledge.stock_items
FOR EACH ROW
EXECUTE FUNCTION knowledge.update_article_counts();

-- コメント追加/削除
CREATE TRIGGER comments_insert
AFTER INSERT ON knowledge.comments
FOR EACH ROW
EXECUTE FUNCTION knowledge.update_article_counts();

CREATE TRIGGER comments_delete
AFTER DELETE ON knowledge.comments
FOR EACH ROW
EXECUTE FUNCTION knowledge.update_article_counts();

-- コメント likes
CREATE TRIGGER comment_likes_insert
AFTER INSERT ON knowledge.comment_likes
FOR EACH ROW
EXECUTE FUNCTION knowledge.update_comment_like_count();

CREATE TRIGGER comment_likes_delete
AFTER DELETE ON knowledge.comment_likes
FOR EACH ROW
EXECUTE FUNCTION knowledge.update_comment_like_count();

-- webhooks
CREATE TABLE IF NOT EXISTS knowledge.webhooks (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    name VARCHAR(100) NOT NULL,
    scope VARCHAR(20) NOT NULL DEFAULT 'system',
    owner_user_id UUID REFERENCES knowledge.users(id) ON DELETE CASCADE,
    provider VARCHAR(30) NOT NULL DEFAULT 'generic',
    url TEXT NOT NULL,
    http_method VARCHAR(10) NOT NULL DEFAULT 'POST',
    payload_template JSONB NOT NULL DEFAULT '{}'::jsonb,
    event_type VARCHAR(100) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT webhooks_scope_check CHECK (scope IN ('system', 'user')),
    CONSTRAINT webhooks_owner_scope_check CHECK (
        (scope = 'system' AND owner_user_id IS NULL)
        OR (scope = 'user' AND owner_user_id IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS knowledge.webhook_headers (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    webhook_id UUID NOT NULL REFERENCES knowledge.webhooks(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    value TEXT NOT NULL,
    is_secret BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT webhook_headers_name_unique UNIQUE (webhook_id, name)
);

CREATE TABLE IF NOT EXISTS knowledge.webhook_deliveries (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    webhook_id UUID NOT NULL REFERENCES knowledge.webhooks(id) ON DELETE CASCADE,
    event_type VARCHAR(100) NOT NULL,
    success BOOLEAN NOT NULL,
    status_code INTEGER,
    duration_ms INTEGER,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_webhooks_scope
    ON knowledge.webhooks(scope);

CREATE INDEX IF NOT EXISTS idx_webhooks_owner_user_id
    ON knowledge.webhooks(owner_user_id);

CREATE INDEX IF NOT EXISTS idx_webhooks_is_active
    ON knowledge.webhooks(is_active);

CREATE INDEX IF NOT EXISTS idx_webhooks_event_type
    ON knowledge.webhooks(event_type);

CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_webhook_id_created_at
    ON knowledge.webhook_deliveries(webhook_id, created_at DESC);

COMMENT ON TABLE knowledge.webhooks IS '汎用Webhook定義';
COMMENT ON COLUMN knowledge.webhooks.scope IS 'Webhookの適用範囲(system/user)';
COMMENT ON COLUMN knowledge.webhooks.owner_user_id IS 'user scopeの場合の所有ユーザ';
COMMENT ON COLUMN knowledge.webhooks.provider IS 'generic/discord/slack/teams等のPreset識別子';
COMMENT ON COLUMN knowledge.webhooks.payload_template IS '送信時に評価するJSON payload template';
COMMENT ON COLUMN knowledge.webhooks.event_type IS '購読する単一Webhook event';
COMMENT ON TABLE knowledge.webhook_headers IS 'Webhook送信時に追加するHTTP Header';
COMMENT ON COLUMN knowledge.webhook_headers.is_secret IS 'UI/ログで値を秘匿すべきHeaderか';
COMMENT ON TABLE knowledge.webhook_deliveries IS 'Webhook配信結果履歴';
