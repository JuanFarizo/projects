
const downloadBtn = document.getElementById('downloadBtn');
const progressBar = document.getElementById('progressBar');

downloadBtn.addEventListener('click', async () => {
  try {
    // Start fetching the file from the server.
    const response = await fetch('/download');

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    // Get the total size of the file from the 'content-length' header.
    const contentLength = response.headers.get('content-length');
    if (!contentLength) {
      console.error('Content-Length header not found.');
      return;
    }

    const total = parseInt(contentLength, 10);
    let loaded = 0;

    // Get a reader from the response body to read the data in chunks.
    const reader = response.body.getReader();

    // Create a new ReadableStream to process the chunks as they arrive.
    const stream = new ReadableStream({
      start(controller) {
        function push() {
          // Read the next chunk of data.
          reader.read().then(({ done, value }) => {
            // If 'done' is true, the download is complete.
            if (done) {
              controller.close();
              return;
            }

            // 'value' is the chunk of data as a Uint8Array.
            // Add the length of the chunk to our running total.
            loaded += value.length;
            // Calculate the download percentage.
            const percentage = Math.round((loaded / total) * 100);
            // Update the progress bar's width and text.
            progressBar.style.width = `${percentage}%`;
            progressBar.textContent = `${percentage}%`;

            // Pass the chunk to the new stream.
            controller.enqueue(value);
            // Continue reading the next chunk.
            push();
          }).catch(error => {
            console.error('Error in stream reading:', error);
            controller.error(error);
          });
        }

        push();
      }
    });

    // Create a new response from our processed stream.
    const newResponse = new Response(stream);
    // Convert the response into a Blob (a file-like object).
    const blob = await newResponse.blob();
    // Create a temporary URL for the blob.
    const url = window.URL.createObjectURL(blob);

    // Create a hidden anchor element to trigger the download.
    const a = document.createElement('a');
    a.style.display = 'none';
    a.href = url;
    a.download = 'dummy-file.bin'; // The desired filename.
    document.body.appendChild(a);
    a.click();

    // Clean up by revoking the temporary URL.
    window.URL.revokeObjectURL(url);

  } catch (error) {
    console.error('Download failed:', error);
  }
});
