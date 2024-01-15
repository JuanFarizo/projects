import { useEffect, useRef, useState } from 'react';

const BASE_URL = 'https://jsonplaceholder.typicode.com';

interface Post {
  id: number;
  title: string;
}

export const Demo = () => {
  const [error, setError] = useState();
  const [isLoading, setIsLoading] = useState(false);
  const [posts, setPosts] = useState<Post[]>([]);
  const [page, setPage] = useState(1);

  //AbortController object allows us to cancel the request
  const abortControllerRef = useRef<AbortController | null>(null);

  useEffect(() => {
    const fetchPost = async () => {
      abortControllerRef.current?.abort(); // If there is a fetch previous that isn't finished and the
      //user want to clic again, in order to cancel the previous one we do this
      abortControllerRef.current = new AbortController(); //Need to be created again because is not reusable

      setIsLoading(true);
      try {
        const response = await fetch(`${BASE_URL}/posts?page=${page}`, {
          signal: abortControllerRef.current?.signal,
        });
        const posts = (await response.json()) as Post[];
        setPosts(posts);
      } catch (error: any) {
        if (error.name === 'AbortError') {
          console.log('Aborted');
          return;
        }
        setError(error);
      } finally {
        setIsLoading(false);
      }
    };
    fetchPost();
  }, [page]); //Dependency array

  if (error) {
    return <div>Something went wrokg try again</div>;
  }

  if (isLoading) {
    return <div>Is Loading....</div>;
  }

  return (
    <div className="tutorial">
      <h1 className="mb-4 text-2xl">Data fetchin in react </h1>
      <button
        type="button"
        onClick={() => {
          setPage(page + 1);
        }}
      >
        Increase the page ({page})
      </button>
      {isLoading && <div>Is Loading....</div>}
      {!isLoading && (
        <ul>
          {posts.map((post) => {
            return <li key={post.id}>{post.title}</li>;
          })}
        </ul>
      )}
    </div>
  );
};
