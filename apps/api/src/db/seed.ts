import argon2 from 'argon2';
import { pool, withTransaction } from './index.js';

const names = ['Mohammed', 'Lama', 'Abdullah', 'Ibrahim', 'Shorouq'];
const channelNames = ['general', 'backend', 'mobile', 'design', 'random'];
const passwordHash = await argon2.hash('PulseMeshDemo123!', { type: argon2.argon2id });

const rolePermissions: Record<string, string[]> = {
  Admin: [
    'workspace.manage','workspace.invite','workspace.roles.manage',
    'channel.create','channel.update','channel.delete',
    'message.send','message.delete','message.pin',
    'member.kick','member.ban','call.create','call.manage',
    'moderation.manage',
    'moderation.manage','audit.view'
  ],
  Moderator: [
    'message.send','message.delete','message.pin',
    'member.kick','member.ban','call.create','call.manage'
  ],
  Member: ['message.send','call.create'],
  Guest: ['message.send']
};

await withTransaction(async (client) => {
  const people: Array<{ id: string; displayName: string }> = [];
  for (const displayName of names) {
    const username = displayName.toLowerCase();
    const result = await client.query<{ id: string }>(
      'INSERT INTO users (email,username,display_name,password_hash,email_verified_at) VALUES ($1,$2,$3,$4,now()) ON CONFLICT (email) DO UPDATE SET display_name=EXCLUDED.display_name RETURNING id',
      [username + '@pulsemesh.demo', username, displayName, passwordHash]
    );
    const row = result.rows[0];
    if (row) people.push({ id: row.id, displayName });
  }

  const owner = people[0];
  if (!owner) throw new Error('Demo owner missing');

  const workspaceResult = await client.query<{ id: string }>(
    'INSERT INTO workspaces (name,slug,description,owner_user_id) VALUES ($1,$2,$3,$4) ON CONFLICT (slug) DO UPDATE SET name=EXCLUDED.name RETURNING id',
    ['The Null Catchers', 'the-null-catchers', 'Realtime product engineering workspace', owner.id]
  );
  const workspaceId = workspaceResult.rows[0]?.id;
  if (!workspaceId) throw new Error('Demo workspace missing');

  const permissions = await client.query<{ id: string; key: string }>('SELECT id,key FROM permissions');
  const roleIds = new Map<string,string>();

  for (const roleName of ['Owner','Admin','Moderator','Member','Guest']) {
    const role = await client.query<{ id: string }>(
      'INSERT INTO roles (workspace_id,name,is_system) VALUES ($1,$2,true) ON CONFLICT (workspace_id,name) DO UPDATE SET name=EXCLUDED.name RETURNING id',
      [workspaceId, roleName]
    );
    const roleId = role.rows[0]?.id;
    if (!roleId) continue;
    roleIds.set(roleName, roleId);

    const keys = roleName === 'Owner'
      ? permissions.rows.map((item) => item.key)
      : rolePermissions[roleName] ?? [];

    await client.query(
      'INSERT INTO role_permissions (role_id,permission_id) SELECT $1,id FROM permissions WHERE key=ANY($2::text[]) ON CONFLICT DO NOTHING',
      [roleId, keys]
    );
  }

  for (const person of people) {
    await client.query(
      'INSERT INTO workspace_members (workspace_id,user_id,role_id) VALUES ($1,$2,$3) ON CONFLICT (workspace_id,user_id) DO UPDATE SET role_id=EXCLUDED.role_id',
      [workspaceId, person.id, roleIds.get(person.id === owner.id ? 'Owner' : 'Member')]
    );
  }

  for (let index = 0; index < channelNames.length; index += 1) {
    await client.query(
      'INSERT INTO channels (workspace_id,name,kind,visibility,position,created_by) VALUES ($1,$2,\'text\',\'public\',$3,$4) ON CONFLICT (workspace_id,name) DO UPDATE SET position=EXCLUDED.position',
      [workspaceId, channelNames[index], index, owner.id]
    );
  }

  await client.query(
    'INSERT INTO channels (workspace_id,name,kind,visibility,position,created_by) VALUES ($1,\'daily-sync\',\'voice\',\'public\',20,$2) ON CONFLICT (workspace_id,name) DO NOTHING',
    [workspaceId, owner.id]
  );

  const backend = await client.query<{ id: string }>(
    'SELECT id FROM channels WHERE workspace_id=$1 AND name=\'backend\'',
    [workspaceId]
  );
  const backendId = backend.rows[0]?.id;
  if (backendId) {
    const existing = await client.query('SELECT 1 FROM messages WHERE channel_id=$1 LIMIT 1', [backendId]);
    if (!existing.rowCount) {
      const samples = [
        ['Mohammed','API deployment finished. Health checks are green and Redis fanout is passing across both replicas.'],
        ['Lama','Great. I will test reconnect, optimistic messages, and missed-message sync from Android now.'],
        ['Ibrahim','TURN is reachable too. I added the production firewall notes to the deployment checklist.']
      ];
      for (const [name, body] of samples) {
        const person = people.find((item) => item.displayName === name);
        if (person) {
          await client.query(
            'INSERT INTO messages (channel_id,sender_user_id,body) VALUES ($1,$2,$3)',
            [backendId, person.id, body]
          );
        }
      }
      const firstMessage = await client.query<{ id: string }>(
        'SELECT id FROM messages WHERE channel_id=$1 ORDER BY created_at,id LIMIT 1',
        [backendId]
      );
      const firstId = firstMessage.rows[0]?.id;
      if (firstId) {
        for (const person of people.slice(0,4)) {
          await client.query(
            'INSERT INTO message_reactions (message_id,user_id,emoji) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING',
            [firstId, person.id, '👍']
          );
        }
      }
    }
  }

  if (people[1]) {
    const dmExists = await client.query<{ id: string }>(
      'SELECT c.id FROM conversations c JOIN conversation_members a ON a.conversation_id=c.id AND a.user_id=$1 JOIN conversation_members b ON b.conversation_id=c.id AND b.user_id=$2 WHERE c.kind=\'direct\' LIMIT 1',
      [owner.id, people[1].id]
    );
    if (!dmExists.rowCount) {
      const conversation = await client.query<{ id: string }>(
        'INSERT INTO conversations (kind,owner_user_id) VALUES (\'direct\',$1) RETURNING id',
        [owner.id]
      );
      const conversationId = conversation.rows[0]?.id;
      if (conversationId) {
        await client.query(
          'INSERT INTO conversation_members (conversation_id,user_id,role) VALUES ($1,$2,\'owner\'),($1,$3,\'member\')',
          [conversationId, owner.id, people[1].id]
        );
      }
    }
  }
});

await pool.end();
console.log('PulseMesh demo seed is ready.');
