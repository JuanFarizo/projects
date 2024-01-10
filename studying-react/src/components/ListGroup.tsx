import { useState } from 'react';
//Each component has his own state
interface Props {
  //Props are the input of the components
  items: string[];
  heading: string;
  // To pass information to the parent we can use a function the convetion the naming start with on
  onSelectItem: (item: string) => void; //function parameter item and return void
}

function ListGroup({ items, heading, onSelectItem }: Props) {
  //To declare data (state) in the component that may change over time
  // can use a hook named useState
  const [selectedIndex, setSelectedIndex] = useState(-1); //arr[0] variable (selectedIndex) arr[1] updater function (can update the variable in position 0 and re-render the component)

  return (
    <>
      <h1>{heading}</h1>
      {items.length === 0 && <p>No Items</p>}{' '}
      {/* If the condition is true renders whatever is next to the && */}
      <ul className="list-group">
        {items.map((item, index) => (
          <li
            className={
              selectedIndex === index
                ? 'list-group-item active'
                : 'list-group-item'
            }
            key={item}
            onClick={() => {
              setSelectedIndex(index);
              onSelectItem(item);
            }}
          >
            {item}
          </li>
        ))}
      </ul>
    </>
  );
}

export default ListGroup;
