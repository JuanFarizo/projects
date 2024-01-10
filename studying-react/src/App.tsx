import { useState } from 'react';
import Alert from './components/Alert';
import Button from './components/Button';
import ListGroup from './components/ListGroup';
import Input from './components/Input';
import ContainerStyle from './components/ContainerStyle';
function App() {
  let items = ['New York', 'Pergamino', 'Paris', 'Rancagua'];

  //Function variable writing
  const handleSelectedItem = (item: string) => {
    console.log(item);
  };
  const handleOnChangeInput = (event: React.ChangeEvent<HTMLInputElement>) => {
    console.log(event.timeStamp);
  };
  // Hook to manage state of the component
  const [alertVisible, setAlertVisibility] = useState(false);
  return (
    <>
      {alertVisible && (
        <Alert onClose={() => setAlertVisibility(false)}> My Alert</Alert>
      )}
      <div>
        <Button
          description="Simple Button"
          handleOnClick={() => setAlertVisibility(true)}
        />
      </div>
      {/*  <div>
        <ListGroup
          items={items}
          heading="Cities"
          onSelectItem={handleSelectedItem}
        />
      </div> */}

      {
        <Input
          inputValue="Write your value here"
          handleOnChange={handleOnChangeInput}
        />
      }

      {
        <ContainerStyle
          style={{ border: '1px solid black', padding: '1erm' }}
        />
      }
    </>
  );
}

export default App;
