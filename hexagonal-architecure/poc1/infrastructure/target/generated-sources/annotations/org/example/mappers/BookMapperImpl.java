package org.example.mappers;

import java.util.ArrayList;
import java.util.List;
import javax.annotation.processing.Generated;
import org.example.data.BookDto;
import org.example.data.BookDto.BookDtoBuilder;
import org.example.entity.Book;
import org.example.entity.Book.BookBuilder;

@Generated(
    value = "org.mapstruct.ap.MappingProcessor",
    date = "2024-08-17T12:03:27-0300",
    comments = "version: 1.4.2.Final, compiler: Eclipse JDT (IDE) 3.39.0.v20240725-1906, environment: Java 17.0.11 (Eclipse Adoptium)"
)
public class BookMapperImpl implements BookMapper {

    @Override
    public BookDto bookToBookDto(Book book) {
        if ( book == null ) {
            return null;
        }

        BookDtoBuilder bookDto = BookDto.builder();

        bookDto.description( book.getDescription() );
        bookDto.id( book.getId() );
        bookDto.price( book.getPrice() );
        bookDto.title( book.getTitle() );

        return bookDto.build();
    }

    @Override
    public Book bookDtoToBook(BookDto bookDto) {
        if ( bookDto == null ) {
            return null;
        }

        BookBuilder book = Book.builder();

        book.description( bookDto.getDescription() );
        book.id( bookDto.getId() );
        book.price( bookDto.getPrice() );
        book.title( bookDto.getTitle() );

        return book.build();
    }

    @Override
    public List<BookDto> bookListToBookDtoList(List<Book> bookList) {
        if ( bookList == null ) {
            return null;
        }

        List<BookDto> list = new ArrayList<BookDto>( bookList.size() );
        for ( Book book : bookList ) {
            list.add( bookToBookDto( book ) );
        }

        return list;
    }

    @Override
    public List<Book> bookDtoListTobookList(List<BookDto> BookDtoList) {
        if ( BookDtoList == null ) {
            return null;
        }

        List<Book> list = new ArrayList<Book>( BookDtoList.size() );
        for ( BookDto bookDto : BookDtoList ) {
            list.add( bookDtoToBook( bookDto ) );
        }

        return list;
    }
}
