import dgram from 'node:dgram';
import crypto from 'node:crypto';

function encodeDnsName(name) {
  const buf = [];
  const labels = name.split('.');
  for (const label of labels) {
    if (label.length > 63) throw new Error(`Label too long: ${label}`);
    buf.push(Buffer.from([label.length]));
    buf.push(Buffer.from(label, 'ascii'));
  }
  buf.push(Buffer.from([0]));
  return Buffer.concat(buf);
}

function buildDnsHeader() {
  const header = Buffer.alloc(12);
  header.writeUInt16BE(crypto.randomInt(0, 65536), 0);
  header.writeUInt16BE(0x8400, 2);
  header.writeUInt16BE(1, 4);
  header.writeUInt16BE(4, 6);
  header.writeUInt16BE(0, 8);
  header.writeUInt16BE(0, 10);
  return header;
}

function buildPtrRecord(name, target, ttl) {
  const nameBuf = encodeDnsName(name);
  const targetBuf = encodeDnsName(target);
  const record = Buffer.alloc(nameBuf.length + 10 + targetBuf.length);
  nameBuf.copy(record);
  const offset = nameBuf.length;
  record.writeUInt16BE(12, offset);
  record.writeUInt16BE(1, offset + 2);
  record.writeUInt32BE(ttl, offset + 4);
  record.writeUInt16BE(targetBuf.length, offset + 8);
  targetBuf.copy(record, offset + 10);
  return record;
}

function buildSrvRecord(name, priority, weight, port, target, ttl) {
  const nameBuf = encodeDnsName(name);
  const targetBuf = encodeDnsName(target);
  const record = Buffer.alloc(nameBuf.length + 10 + 6 + targetBuf.length);
  nameBuf.copy(record);
  let offset = nameBuf.length;
  record.writeUInt16BE(33, offset);
  record.writeUInt16BE(1, offset + 2);
  record.writeUInt32BE(ttl, offset + 4);
  record.writeUInt16BE(6 + targetBuf.length, offset + 8);
  offset += 10;
  record.writeUInt16BE(priority, offset);
  record.writeUInt16BE(weight, offset + 2);
  record.writeUInt16BE(port, offset + 4);
  targetBuf.copy(record, offset + 6);
  return record;
}

function buildTxtRecord(name, props, ttl) {
  const entries = [];
  for (const [key, value] of Object.entries(props)) {
    const entry = `${key}=${value}`;
    if (entry.length > 255) continue;
    entries.push(Buffer.from([entry.length]));
    entries.push(Buffer.from(entry, 'ascii'));
  }
  const txtData = Buffer.concat(entries);
  const nameBuf = encodeDnsName(name);
  const record = Buffer.alloc(nameBuf.length + 10 + txtData.length);
  nameBuf.copy(record);
  const offset = nameBuf.length;
  record.writeUInt16BE(16, offset);
  record.writeUInt16BE(1, offset + 2);
  record.writeUInt32BE(ttl, offset + 4);
  record.writeUInt16BE(txtData.length, offset + 8);
  txtData.copy(record, offset + 10);
  return record;
}

const MDNS_MULTICAST_ADDR = '224.0.0.251';
const MDNS_PORT = 5353;

export class MDNSAdvertiser {
  constructor({ instanceName, serviceType, port, txtProps, log }) {
    this.instanceName = cleanDnsLabel(instanceName);
    this.serviceType = serviceType;
    this.port = port;
    this.txtProps = txtProps || {};
    this.log = log || (() => {});
    this._socket = null;
    this._timer = null;
    this._announceCount = 0;

    const hostname = cleanDnsLabel(this.instanceName);
    this._serviceInstance = `${hostname}.${this.serviceType}.local`;
    this._hostTarget = `${hostname}.local`;
  }

  start(initialDelayMs = 1000, intervalMs = 30000) {
    if (this._socket) return;

    this._socket = dgram.createSocket({ type: 'udp4', reuseAddr: true });

    this._socket.on('error', (err) => {
      this.log('error', `mDNS advertiser error: ${err.message}`);
    });

    this._socket.on('message', (msg, rinfo) => {
      try {
        this._handleQuery(msg, rinfo);
      } catch (_) {}
    });

    this._socket.bind(MDNS_PORT, () => {
      this._socket.setMulticastTTL(255);
      this._socket.setMulticastLoopback(true);

      this._announceCount = 0;
      this._sendAnnouncement();

      this._timer = setInterval(() => {
        this._sendAnnouncement();
      }, intervalMs);

      this.log('info', `mDNS advertiser started: ${this._serviceInstance}`);
    });
  }

  stop() {
    if (this._timer) {
      clearInterval(this._timer);
      this._timer = null;
    }

    if (this._socket) {
      try {
        this._sendGoodbye();
      } catch (_) {}

      try {
        this._socket.close();
      } catch (_) {}
      this._socket = null;
    }
  }

  _sendAnnouncement() {
    if (!this._socket) return;

    const ttl = 120;
    const header = buildDnsHeader();
    const ptr = buildPtrRecord(this.serviceType + '.local', this._serviceInstance, ttl);
    const srv = buildSrvRecord(this._serviceInstance, 0, 0, this.port, this._hostTarget, ttl);
    const txt = buildTxtRecord(this._serviceInstance, this.txtProps, ttl);

    const message = Buffer.concat([header, ptr, srv, txt]);
    this._socket.send(message, 0, message.length, MDNS_PORT, MDNS_MULTICAST_ADDR);

    this._announceCount += 1;
  }

  _sendGoodbye() {
    if (!this._socket) return;

    const ttl = 0;
    const header = buildDnsHeader();
    header.writeUInt16BE(0x8400, 2);

    const ptr = buildPtrRecord(this.serviceType + '.local', this._serviceInstance, ttl);
    const srv = buildSrvRecord(this._serviceInstance, 0, 0, this.port, this._hostTarget, ttl);
    const txt = buildTxtRecord(this._serviceInstance, this.txtProps, ttl);

    const message = Buffer.concat([header, ptr, srv, txt]);
    this._socket.send(message, 0, message.length, MDNS_PORT, MDNS_MULTICAST_ADDR);
  }

  _handleQuery(msg, rinfo) {
    if (!this._socket || rinfo.address === this._socket.address()?.address) return;

    const questions = this._parseQuestions(msg);
    if (questions.length === 0) return;

    const relevant = questions.some(
      (q) =>
        q === this.serviceType + '.local' ||
        q === this._serviceInstance,
    );

    if (relevant) {
      setTimeout(() => this._sendAnnouncement(), 20 + Math.random() * 100);
    }
  }

  _parseQuestions(msg) {
    if (msg.length < 12) return [];
    const qdCount = msg.readUInt16BE(4);
    const questions = [];
    let offset = 12;

    for (let i = 0; i < qdCount; i++) {
      const { name, nextOffset } = readDnsName(msg, offset);
      if (name) questions.push(name);
      offset = nextOffset + 4;
      if (offset >= msg.length) break;
    }

    return questions;
  }
}

function cleanDnsLabel(str) {
  return String(str || '')
    .replace(/[^a-zA-Z0-9-]/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 63) || 'device';
}

function readDnsName(buf, offset) {
  const labels = [];
  let pos = offset;
  let jumped = false;
  const maxJumps = 10;
  let jumps = 0;

  while (jumps < maxJumps) {
    if (pos >= buf.length) break;
    const len = buf[pos];

    if (len === 0) {
      if (!jumped) pos += 1;
      break;
    }

    if ((len & 0xc0) === 0xc0) {
      if (pos + 2 > buf.length) break;
      pos = ((len & 0x3f) << 8) | buf[pos + 1];
      jumped = true;
      jumps += 1;
      continue;
    }

    pos += 1;
    if (pos + len > buf.length) break;
    labels.push(buf.slice(pos, pos + len).toString('ascii'));
    pos += len;
  }

  return { name: labels.join('.'), nextOffset: pos };
}
