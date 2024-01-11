import { useRef, useEffect } from 'react';

function DomRef() {
  const inputRef = useRef<HTMLInputElement>(null!); //Is a input element so we have to specify
  //And can negate the null to specify only not Null are accepted

  useEffect(() => {
    inputRef.current.focus();
  }, []);

  return (
    <div>
      <input type="text" ref={inputRef} />
    </div>
  );
}

export default DomRef;