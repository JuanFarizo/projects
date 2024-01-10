import { MouseEvent } from 'react';

function ListGroup() {
  const items = ['New York', 'Pergamino', 'Paris', 'Rancagua'];

  //Event handler
  const handleEvent = (event: MouseEvent) => console.log(event);

  return (
    <>
      <h1>List</h1>
      {items.length === 0 && <p>No Items</p>}{' '}
      {/* If the condition is true renders whatever is next to the && */}
      <ul className="list-group">
        {items.map((item) => (
          <li className="list-group-item" onClick={handleEvent} key={item}>
            {item}
          </li>
        ))}
      </ul>
    </>
  );
}

export default ListGroup;
