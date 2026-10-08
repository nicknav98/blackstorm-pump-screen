// Builds a framed request for the BY/CPS pump-screen protocol and prints it as hex.
// usage: node frame.js <METHOD> <command> [jsonBody]
const FLAG = 0x5a, ESC = 0x5b;

function checksum(data) {
  const len = data.length + 5;
  let sum = (len >> 8) + (len & 0xff);
  for (const b of data) sum += b;
  return sum & 0xff;
}

function escape(buf) {
  const out = [];
  for (const b of buf) {
    if (b === FLAG) out.push(ESC, 1);
    else if (b === ESC) out.push(ESC, 2);
    else out.push(b);
  }
  return Buffer.from(out);
}

function frame(data) {
  const inner = Buffer.alloc(data.length + 3);
  inner.writeUInt16BE(data.length + 5, 0);
  data.copy(inner, 2);
  inner[inner.length - 1] = checksum(data);
  return Buffer.concat([Buffer.from([FLAG]), escape(inner), Buffer.from([FLAG])]);
}

function request(method, command, body, seq = 1) {
  let headers = `SeqNumber=${seq}\r\nDate=${Date.now()}\r\n`;
  if (body) headers += `ContentType=json\r\nContentLength=${body.length}\r\n`;
  return frame(Buffer.from(`${method} ${command} 1\r\n${headers}\r\n${body || ''}`, 'latin1'));
}

module.exports = { frame, request, escape, checksum };

if (require.main === module) {
  const [, , method, command, body] = process.argv;
  process.stdout.write(request(method, command, body).toString('hex'));
}
