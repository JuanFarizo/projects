
const express = require('express');
const path = require('path');
const app = express();
const port = 3000;

// Serve static files from the "public" directory
app.use(express.static(path.join(__dirname, 'public')));

// Route to handle the file download
app.get('/download', (req, res) => {
  const filePath = path.join(__dirname, 'files', 'dummy-file.bin');
  res.download(filePath, 'dummy-file.bin', (err) => {
    if (err) {
      console.error('Error downloading file:', err);
    }
  });
});

app.listen(port, () => {
  console.log(`Server running at http://localhost:${port}`);
});
