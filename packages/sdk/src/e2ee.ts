export type E2eeProtocol = 'libsignal-v1';

export interface E2eePublicDeviceBundle {
  registrationId: number;
  identityKeyPublic: string;
  signedPreKey: {
    id: number;
    publicKey: string;
    signature: string;
  };
  oneTimePreKeys: Array<{
    id: number;
    publicKey: string;
  }>;
}

export interface E2eePeerDeviceBundle {
  deviceSessionId: string;
  registrationId: number;
  identityKeyPublic: string;
  signedPreKey: {
    id: number;
    publicKey: string;
    signature: string;
  };
  oneTimePreKey: {
    id: number;
    publicKey: string;
  } | null;
  revision: string;
}

export interface E2eeCiphertext {
  protocol: E2eeProtocol;
  payload: string;
}

/**
 * Crypto implementation boundary for optional direct-message E2EE.
 *
 * Implementations must delegate protocol state, key agreement, ratcheting,
 * authentication and encryption to an established Signal Protocol library.
 * PulseMesh deliberately does not provide custom cryptographic primitives.
 * Private identity keys, session state and decrypted plaintext stay on-device.
 */
export interface E2eeCryptoProvider {
  readonly protocol: E2eeProtocol;

  createOrRotateBundle(): Promise<E2eePublicDeviceBundle>;

  establishPeerSessions(input: {
    conversationId: string;
    peerUserId: string;
    devices: E2eePeerDeviceBundle[];
  }): Promise<void>;

  encrypt(input: {
    conversationId: string;
    plaintext: string;
  }): Promise<E2eeCiphertext>;

  decrypt(input: {
    conversationId: string;
    senderUserId: string;
    ciphertext: E2eeCiphertext;
  }): Promise<string>;

  destroyConversationState(conversationId: string): Promise<void>;
}
