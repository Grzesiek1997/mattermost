"use client"

import { useState } from "react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { SUPABASE_READY } from "@/lib/supabase"
import { Copy, ExternalLink, Database, Settings, Code, CheckCircle } from "lucide-react"
import { toast } from "@/hooks/use-toast"

export function SupabaseSetupGuide() {
  const [copied, setCopied] = useState<string | null>(null)

  const copyToClipboard = (text: string, label: string) => {
    navigator.clipboard.writeText(text)
    setCopied(label)
    toast({
      title: "Copied!",
      description: `${label} copied to clipboard`,
    })
    setTimeout(() => setCopied(null), 2000)
  }

  const sqlScripts = [
    {
      name: "01-database-schema.sql",
      description: "Core database tables and indexes",
      content: `-- Core Users Table with Extended Profiles
CREATE TABLE IF NOT EXISTS users (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  username TEXT UNIQUE,
  full_name TEXT,
  bio TEXT,
  avatar_url TEXT,
  phone TEXT,
  is_online BOOLEAN DEFAULT false,
  last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Chats Table (Groups, Channels, Direct Messages)
CREATE TABLE IF NOT EXISTS chats (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  type TEXT CHECK (type IN ('direct', 'group', 'channel')) NOT NULL,
  title TEXT,
  description TEXT,
  avatar_url TEXT,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  last_message_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Chat Members with Roles and Permissions
CREATE TABLE IF NOT EXISTS chat_members (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  chat_id UUID REFERENCES chats(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  role TEXT CHECK (role IN ('owner', 'admin', 'member')) DEFAULT 'member',
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  can_send_messages BOOLEAN DEFAULT true,
  can_add_members BOOLEAN DEFAULT false,
  can_delete_messages BOOLEAN DEFAULT false,
  UNIQUE(chat_id, user_id)
);

-- Messages with Threading and Rich Content
CREATE TABLE IF NOT EXISTS messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  chat_id UUID REFERENCES chats(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id),
  content TEXT,
  message_type TEXT CHECK (message_type IN ('text', 'image', 'file', 'voice', 'video')) DEFAULT 'text',
  file_url TEXT,
  file_name TEXT,
  file_size INTEGER,
  reply_to_id UUID REFERENCES messages(id),
  thread_id UUID REFERENCES messages(id),
  is_edited BOOLEAN DEFAULT false,
  is_deleted BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Message Reactions
CREATE TABLE IF NOT EXISTS message_reactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  emoji TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(message_id, user_id, emoji)
);

-- Message Read Status
CREATE TABLE IF NOT EXISTS message_reads (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(message_id, user_id)
);

-- Contacts and Relationships
CREATE TABLE IF NOT EXISTS contacts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  contact_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  status TEXT CHECK (status IN ('pending', 'accepted', 'blocked')) DEFAULT 'accepted',
  invited_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  accepted_at TIMESTAMP WITH TIME ZONE,
  blocked_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, contact_user_id)
);

-- Typing Indicators
CREATE TABLE IF NOT EXISTS typing_indicators (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  chat_id UUID REFERENCES chats(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  is_typing BOOLEAN DEFAULT false,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(chat_id, user_id)
);

-- Create Indexes for Performance
CREATE INDEX IF NOT EXISTS idx_messages_chat_id_created_at ON messages(chat_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_user_id ON messages(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_reply_to_id ON messages(reply_to_id);
CREATE INDEX IF NOT EXISTS idx_chat_members_chat_id ON chat_members(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_members_user_id ON chat_members(user_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_message_id ON message_reactions(message_id);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_contacts_status ON contacts(status);
CREATE INDEX IF NOT EXISTS idx_contacts_user_id ON contacts(user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_contact_user_id ON contacts(contact_user_id);

-- Enable Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE typing_indicators ENABLE ROW LEVEL SECURITY;`,
    },
    {
      name: "02-rls-policies.sql",
      description: "Row Level Security policies",
      content: `-- RLS Policies for Security

-- Users can read all profiles (for search functionality)
CREATE POLICY "Authenticated users can read all users" ON users
  FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON users
  FOR INSERT WITH CHECK (auth.uid() = id);

-- Chat access policies
CREATE POLICY "Users can read chats they are members of" ON chats
  FOR SELECT USING (
    id IN (
      SELECT chat_id FROM chat_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create chats" ON chats
  FOR INSERT WITH CHECK (created_by = auth.uid());

-- Chat members policies
CREATE POLICY "Users can read chat members of their chats" ON chat_members
  FOR SELECT USING (
    chat_id IN (
      SELECT chat_id FROM chat_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can add members to chats they admin" ON chat_members
  FOR INSERT WITH CHECK (
    chat_id IN (
      SELECT chat_id FROM chat_members 
      WHERE user_id = auth.uid() AND (role = 'owner' OR role = 'admin' OR can_add_members = true)
    )
  );

-- Messages policies
CREATE POLICY "Users can read messages from their chats" ON messages
  FOR SELECT USING (
    chat_id IN (
      SELECT chat_id FROM chat_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can send messages to their chats" ON messages
  FOR INSERT WITH CHECK (
    user_id = auth.uid() AND
    chat_id IN (
      SELECT chat_id FROM chat_members 
      WHERE user_id = auth.uid() AND can_send_messages = true
    )
  );

CREATE POLICY "Users can update their own messages" ON messages
  FOR UPDATE USING (user_id = auth.uid());

-- Message reactions policies
CREATE POLICY "Users can read reactions in their chats" ON message_reactions
  FOR SELECT USING (
    message_id IN (
      SELECT m.id FROM messages m
      JOIN chat_members cm ON m.chat_id = cm.chat_id
      WHERE cm.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can add reactions to messages in their chats" ON message_reactions
  FOR INSERT WITH CHECK (
    user_id = auth.uid() AND
    message_id IN (
      SELECT m.id FROM messages m
      JOIN chat_members cm ON m.chat_id = cm.chat_id
      WHERE cm.user_id = auth.uid()
    )
  );

-- Message reads policies
CREATE POLICY "Users can read message read status in their chats" ON message_reads
  FOR SELECT USING (
    message_id IN (
      SELECT m.id FROM messages m
      JOIN chat_members cm ON m.chat_id = cm.chat_id
      WHERE cm.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can mark messages as read" ON message_reads
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- Contacts policies
CREATE POLICY "Users can read their contacts and invitations" ON contacts
  FOR SELECT USING (
    auth.uid() = user_id OR auth.uid() = contact_user_id
  );

CREATE POLICY "Users can send contact invitations" ON contacts
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their contact relationships" ON contacts
  FOR UPDATE USING (
    auth.uid() = user_id OR auth.uid() = contact_user_id
  );

CREATE POLICY "Users can delete their contact relationships" ON contacts
  FOR DELETE USING (
    auth.uid() = user_id OR auth.uid() = contact_user_id
  );

-- Typing indicators policies
CREATE POLICY "Users can read typing indicators in their chats" ON typing_indicators
  FOR SELECT USING (
    chat_id IN (
      SELECT chat_id FROM chat_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update their typing status" ON typing_indicators
  FOR ALL USING (user_id = auth.uid());`,
    },
    {
      name: "03-functions-triggers.sql",
      description: "Database functions and triggers",
      content: `-- Function to update last_seen when user comes online
CREATE OR REPLACE FUNCTION update_user_last_seen()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_online = true AND OLD.is_online = false THEN
    NEW.last_seen = NOW();
  END IF;
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_user_last_seen
  BEFORE UPDATE ON users
  FOR EACH ROW
  EXECUTE FUNCTION update_user_last_seen();

-- Function to update chat's last_message_at when new message is sent
CREATE OR REPLACE FUNCTION update_chat_last_message()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE chats 
  SET last_message_at = NEW.created_at, updated_at = NOW()
  WHERE id = NEW.chat_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_chat_last_message
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION update_chat_last_message();

-- Function to automatically add creator as owner when creating a chat
CREATE OR REPLACE FUNCTION add_chat_creator_as_owner()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO chat_members (chat_id, user_id, role, can_send_messages, can_add_members, can_delete_messages)
  VALUES (NEW.id, NEW.created_by, 'owner', true, true, true);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_add_chat_creator_as_owner
  AFTER INSERT ON chats
  FOR EACH ROW
  EXECUTE FUNCTION add_chat_creator_as_owner();

-- Function to clean up old typing indicators
CREATE OR REPLACE FUNCTION cleanup_typing_indicators()
RETURNS void AS $$
BEGIN
  DELETE FROM typing_indicators 
  WHERE updated_at < NOW() - INTERVAL '10 seconds';
END;
$$ LANGUAGE plpgsql;

-- Function for optimized user search
CREATE OR REPLACE FUNCTION get_searchable_users(
  search_query TEXT,
  current_user_id UUID,
  result_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
  id UUID,
  email TEXT,
  username TEXT,
  full_name TEXT,
  avatar_url TEXT,
  bio TEXT,
  phone TEXT,
  is_online BOOLEAN,
  last_seen TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE,
  updated_at TIMESTAMP WITH TIME ZONE,
  contact_status TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    u.id,
    u.email,
    u.username,
    u.full_name,
    u.avatar_url,
    u.bio,
    u.phone,
    u.is_online,
    u.last_seen,
    u.created_at,
    u.updated_at,
    COALESCE(c.status, 'none') as contact_status
  FROM users u
  LEFT JOIN contacts c ON (
    (c.user_id = current_user_id AND c.contact_user_id = u.id) OR
    (c.contact_user_id = current_user_id AND c.user_id = u.id)
  )
  WHERE 
    u.id != current_user_id
    AND (
      u.username ILIKE '%' || search_query || '%' OR
      u.full_name ILIKE '%' || search_query || '%' OR
      u.email ILIKE '%' || search_query || '%'
    )
  ORDER BY 
    CASE WHEN u.is_online THEN 0 ELSE 1 END,
    u.full_name,
    u.username
  LIMIT result_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_searchable_users TO authenticated;`,
    },
    {
      name: "04-seed-data.sql",
      description: "Sample users for testing",
      content: `-- Insert some test users for development
INSERT INTO users (id, email, username, full_name, bio, is_online, avatar_url) VALUES
  ('11111111-1111-1111-1111-111111111111', 'john.doe@test.com', 'johndoe', 'John Doe', 'Software Developer at Tech Corp', true, '/placeholder.svg?height=40&width=40&text=JD'),
  ('22222222-2222-2222-2222-222222222222', 'jane.smith@test.com', 'janesmith', 'Jane Smith', 'UI/UX Designer | Creative Professional', false, '/placeholder.svg?height=40&width=40&text=JS'),
  ('33333333-3333-3333-3333-333333333333', 'mike.wilson@test.com', 'mikewilson', 'Mike Wilson', 'Product Manager | Tech Enthusiast', true, '/placeholder.svg?height=40&width=40&text=MW'),
  ('44444444-4444-4444-4444-444444444444', 'sarah.johnson@test.com', 'sarahj', 'Sarah Johnson', 'Marketing Specialist | Content Creator', false, '/placeholder.svg?height=40&width=40&text=SJ'),
  ('55555555-5555-5555-5555-555555555555', 'alex.brown@test.com', 'alexbrown', 'Alex Brown', 'Data Scientist | AI/ML Engineer', true, '/placeholder.svg?height=40&width=40&text=AB')
ON CONFLICT (id) DO UPDATE SET
  email = EXCLUDED.email,
  username = EXCLUDED.username,
  full_name = EXCLUDED.full_name,
  bio = EXCLUDED.bio,
  is_online = EXCLUDED.is_online,
  avatar_url = EXCLUDED.avatar_url;

-- Verify the data was inserted
SELECT id, email, username, full_name FROM users ORDER BY created_at DESC LIMIT 10;`,
    },
  ]

  if (SUPABASE_READY) {
    return (
      <Alert className="border-green-200 bg-green-50">
        <CheckCircle className="h-4 w-4 text-green-600" />
        <AlertDescription className="text-green-800">
          ✅ Supabase is connected and ready! Your environment variables are properly configured.
        </AlertDescription>
      </Alert>
    )
  }

  return (
    <div className="max-w-4xl mx-auto p-6 space-y-6">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Database className="h-5 w-5" />
            Supabase Setup Required
          </CardTitle>
          <CardDescription>
            Connect your Telegram Clone app to your Supabase project to enable all features.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Alert className="mb-6">
            <Settings className="h-4 w-4" />
            <AlertDescription>
              <strong>Environment variables are missing.</strong> Please follow the steps below to connect your Supabase
              project.
            </AlertDescription>
          </Alert>

          <Tabs defaultValue="env" className="w-full">
            <TabsList className="grid w-full grid-cols-3">
              <TabsTrigger value="env">Environment Variables</TabsTrigger>
              <TabsTrigger value="sql">Database Setup</TabsTrigger>
              <TabsTrigger value="deploy">Deploy</TabsTrigger>
            </TabsList>

            <TabsContent value="env" className="space-y-4">
              <div className="space-y-4">
                <h3 className="text-lg font-semibold">Step 1: Get Your Supabase Credentials</h3>
                <ol className="list-decimal list-inside space-y-2 text-sm">
                  <li>
                    Go to your{" "}
                    <a
                      href="https://supabase.com/dashboard"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-blue-600 hover:underline inline-flex items-center gap-1"
                    >
                      Supabase Dashboard <ExternalLink className="h-3 w-3" />
                    </a>
                  </li>
                  <li>Select your project</li>
                  <li>Go to Settings → API</li>
                  <li>Copy the Project URL and anon/public key</li>
                </ol>

                <h3 className="text-lg font-semibold">Step 2: Add Environment Variables</h3>
                <p className="text-sm text-gray-600">
                  Add these environment variables to your project (create a <code>.env.local</code> file):
                </p>

                <div className="space-y-3">
                  <div>
                    <Label htmlFor="supabase-url">NEXT_PUBLIC_SUPABASE_URL</Label>
                    <div className="flex gap-2">
                      <Input
                        id="supabase-url"
                        placeholder="https://your-project-ref.supabase.co"
                        className="font-mono text-sm"
                      />
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() =>
                          copyToClipboard("NEXT_PUBLIC_SUPABASE_URL=https://your-project-ref.supabase.co", "URL")
                        }
                      >
                        <Copy className="h-4 w-4" />
                      </Button>
                    </div>
                  </div>

                  <div>
                    <Label htmlFor="supabase-key">NEXT_PUBLIC_SUPABASE_ANON_KEY</Label>
                    <div className="flex gap-2">
                      <Input
                        id="supabase-key"
                        placeholder="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
                        className="font-mono text-sm"
                      />
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => copyToClipboard("NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key", "Anon Key")}
                      >
                        <Copy className="h-4 w-4" />
                      </Button>
                    </div>
                  </div>
                </div>

                <Alert>
                  <Code className="h-4 w-4" />
                  <AlertDescription>
                    <strong>For Vercel deployment:</strong> Add these same variables in your Vercel project settings
                    under Environment Variables.
                  </AlertDescription>
                </Alert>
              </div>
            </TabsContent>

            <TabsContent value="sql" className="space-y-4">
              <div className="space-y-4">
                <h3 className="text-lg font-semibold">Step 3: Set Up Database Schema</h3>
                <p className="text-sm text-gray-600">
                  Run these SQL scripts in your Supabase project's SQL Editor in order:
                </p>

                <div className="space-y-4">
                  {sqlScripts.map((script, index) => (
                    <Card key={script.name}>
                      <CardHeader className="pb-3">
                        <div className="flex items-center justify-between">
                          <div>
                            <CardTitle className="text-sm">
                              <Badge variant="outline" className="mr-2">
                                {index + 1}
                              </Badge>
                              {script.name}
                            </CardTitle>
                            <CardDescription className="text-xs">{script.description}</CardDescription>
                          </div>
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={() => copyToClipboard(script.content, script.name)}
                          >
                            {copied === script.name ? (
                              <CheckCircle className="h-4 w-4" />
                            ) : (
                              <Copy className="h-4 w-4" />
                            )}
                          </Button>
                        </div>
                      </CardHeader>
                      <CardContent>
                        <pre className="text-xs bg-gray-50 p-3 rounded overflow-x-auto max-h-32">
                          {script.content.substring(0, 200)}...
                        </pre>
                      </CardContent>
                    </Card>
                  ))}
                </div>

                <Alert>
                  <Database className="h-4 w-4" />
                  <AlertDescription>
                    <strong>How to run:</strong> Go to your Supabase project → SQL Editor → New query → Paste each
                    script → Run
                  </AlertDescription>
                </Alert>
              </div>
            </TabsContent>

            <TabsContent value="deploy" className="space-y-4">
              <div className="space-y-4">
                <h3 className="text-lg font-semibold">Step 4: Deploy to Vercel</h3>
                <ol className="list-decimal list-inside space-y-2 text-sm">
                  <li>Push your code to GitHub</li>
                  <li>Connect your GitHub repo to Vercel</li>
                  <li>Add the environment variables in Vercel project settings</li>
                  <li>Deploy your project</li>
                </ol>

                <Alert>
                  <ExternalLink className="h-4 w-4" />
                  <AlertDescription>
                    <strong>Quick Deploy:</strong> You can also use the "Deploy" button in the v0 interface to deploy
                    directly to Vercel.
                  </AlertDescription>
                </Alert>
              </div>
            </TabsContent>
          </Tabs>
        </CardContent>
      </Card>
    </div>
  )
}
